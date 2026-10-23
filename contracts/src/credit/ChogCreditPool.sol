// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChogAccountRegistry, ICreditModule} from "../core/interfaces/IChogAccountRegistry.sol";
import {AccountVault} from "../core/AccountVault.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {INonfungiblePositionManager, IUniswapV3Factory, IUniswapV3PoolState} from "./interfaces/IUniswapV3.sol";
import {LpMath} from "./lib/LpMath.sol";
import {IPositionHost} from "../core/interfaces/IChogAccountRegistry.sol";

interface IUniswapV3PoolInfo {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

/// @title ChogCreditPool
/// @notice Lends an existing ERC-20 (for example USDC) against collateral held in Chog account vaults. It never mints
///         the loan token: lenders supply it and receive shares.
///
/// @dev DESIGN CHOICES (read before changing anything)
///  - No owner, no admin, no pause, no upgrade. Every parameter is immutable and set by the constructor; changing one
///    means deploying a new pool. This is deliberate while there is no multisig/timelock to hold such powers.
///  - Bound to the registry once, by `ChogCreditFactory` in the same transaction that deploys both.
///  - Borrowed funds go to the borrower's wallet (the controller), never into the vault, so the vault only ever
///    holds collateral the borrower deposited and liquidation can reach everything that backs the loan.
///  - Debt uses a global index (RAY) so interest accrues per second to every account without per-account writes.
///    Debt rounds UP, collateral value and lender claims round DOWN.
///  - Lender shares are internal (not an ERC-20) with virtual shares/assets to blunt the first-depositor inflation
///    attack. There is no reserve/fee: all interest accrues to lenders. Bad debt is written off against lenders.
///  - Oracle failure fails CLOSED for borrowing, for withdrawals while indebted, and for liquidation. Repayment,
///    supplying, redeeming (cash permitting) and withdrawals by debt-free accounts never need a price.
///  - Collateral caps per asset across all accounts are NOT implemented (R-27); only pool, borrow and per-account caps,
///    plus a per-account `maxCounted` per collateral.
///  - Uniswap V3 positions (optional, docs/LP_COLLATERAL_SPEC.md) are valued at the ORACLE price, never the pool's own
///    price, and a pool that disagrees with the oracle by more than its bound makes the position unpriceable.
contract ChogCreditPool is ICreditModule, IPositionHost, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant RAY = 1e27;
    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 public constant VIRTUAL_SHARES = 1e6;
    uint256 public constant MAX_COLLATERALS = 4;
    uint256 public constant MAX_LP_POOLS = 2;
    uint256 internal constant LP_QUOTE_WHOLE_TOKENS = 1e6; // price probe size, for precision
    uint256 public constant MAX_RATE_BPS = 100_000; // 1000% APR ceiling on the sum of the rate parameters

    struct PoolConfig {
        address loanToken;
        address oracle;
        uint16 closeFactorBps; // max share of an account's debt repayable in one liquidation
        uint256 dustDebt; // debts at or below this may be liquidated in full
        uint256 supplyCap; // max total assets (loan-token raw units)
        uint256 borrowCap; // max total debt
        uint256 accountDebtCap; // max debt per account
        uint16 baseRateBps; // APR at zero utilization
        uint16 slope1Bps; // added APR from 0 to optimal utilization
        uint16 slope2Bps; // added APR from optimal to 100% utilization
        uint16 optimalUtilBps;
        uint16 priorityUtilBps; // above this utilization after a borrow, only vaults at least priorityMinAge old may borrow (0 = off)
        uint32 priorityMinAge; // seconds a vault must have been open to borrow above the line
    }

    struct CollateralConfig {
        address token;
        uint16 ltvBps; // borrowing power
        uint16 liquidationThresholdBps; // above ltv; liquidation when debt exceeds value * threshold
        uint16 liquidationBonusBps;
        uint256 maxCounted; // per-account cap on collateral units counted toward borrowing power and health
    }

    struct Collateral {
        address token;
        uint8 decimals;
        uint16 ltvBps;
        uint16 thresholdBps;
        uint16 bonusBps;
        uint256 maxCounted;
    }

    struct LpPoolConfig {
        address pool; // the Uniswap V3 pool; must be the factory's pool for its own tokens and fee
        uint16 ltvBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 maxDeviationBps; // largest allowed gap between the pool price and the oracle price
        uint256 maxCountedValue; // per-account cap on counted position value (loan-token units)
    }

    struct LpConfig {
        address positionManager; // address(0) disables positions
        LpPoolConfig[] pools;
    }

    struct LpPool {
        address pool;
        address token0;
        address token1;
        uint24 fee;
        uint16 ltvBps;
        uint16 thresholdBps;
        uint16 bonusBps;
        uint16 maxDeviationBps;
        uint256 maxCountedValue;
    }

    struct Valuation {
        bool ok;
        uint256 collateralValue;
        uint256 borrowPower;
        uint256 liquidationValue;
    }

    struct AccountData {
        bool priceOk;
        uint256 debt;
        uint256 collateralValue;
        uint256 borrowPower;
        uint256 liquidationValue;
        uint256 healthFactorBps; // liquidationValue / debt; max if no debt
        uint256 availableToBorrow;
    }

    IChogAccountRegistry public immutable registry;
    IERC20 public immutable loanToken;
    IPriceOracle public immutable oracle;
    uint16 public immutable closeFactorBps;
    uint256 public immutable dustDebt;
    uint256 public immutable supplyCap;
    uint256 public immutable borrowCap;
    uint256 public immutable accountDebtCap;
    uint16 public immutable baseRateBps;
    uint16 public immutable slope1Bps;
    uint16 public immutable slope2Bps;
    uint16 public immutable optimalUtilBps;

    Collateral[] internal _collaterals;

    /// @inheritdoc IPositionHost
    address public immutable positionManager;
    address internal immutable _lpFactory;
    LpPool[] internal _lpPools;

    uint16 public immutable priorityUtilBps;
    uint32 public immutable priorityMinAge;
    uint256 public borrowIndex = RAY;
    uint64 public lastAccrual;
    uint256 public totalScaledDebt;
    mapping(bytes32 => uint256) public debtScaled;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    error ZeroAddress();
    error BadConfig();
    error ZeroAmount();
    error ZeroShares();
    error InsufficientShares(uint256 requested, uint256 owned);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error SupplyCapExceeded(uint256 totalAfter, uint256 cap);
    error BorrowCapExceeded(uint256 totalAfter, uint256 cap);
    error AccountCapExceeded(uint256 debtAfter, uint256 cap);
    error PriorityAccessOnly(uint256 utilAfterBps, uint256 minAge, uint256 age);
    error BorrowLimitExceeded(uint256 debtAfter, uint256 borrowPower);
    error NotController();
    error NotEscrowed();
    error OracleFailure();
    error NoDebt();
    error NotLiquidatable(uint256 debt, uint256 liquidationValue);
    error NothingToSeize();
    error BalanceDeltaMismatch(uint256 expected, uint256 received);

    event Supplied(address indexed lender, uint256 assets, uint256 shares);
    event Redeemed(address indexed lender, uint256 shares, uint256 assets);
    event Borrowed(bytes32 indexed key, address indexed borrower, uint256 amount, uint256 debtAfter);
    event Repaid(bytes32 indexed key, address indexed payer, uint256 amount, uint256 debtAfter);
    event Liquidated(bytes32 indexed key, address indexed liquidator, uint256 repaid, uint256 debtAfter);
    event BadDebtWrittenOff(bytes32 indexed key, uint256 amount);
    event Accrued(uint256 borrowIndex, uint256 rateBps);
    event PositionsUnwound(bytes32 indexed key, uint256 positions, uint256 debtRepaidFromProceeds);

    constructor(address registry_, PoolConfig memory c, CollateralConfig[] memory cols, LpConfig memory lp) {
        if (registry_ == address(0) || c.loanToken == address(0) || c.oracle == address(0)) revert ZeroAddress();
        if (c.closeFactorBps == 0 || c.closeFactorBps > BPS) revert BadConfig();
        if (c.optimalUtilBps == 0 || c.optimalUtilBps >= BPS) revert BadConfig();
        if (uint256(c.baseRateBps) + c.slope1Bps + c.slope2Bps > MAX_RATE_BPS) revert BadConfig();
        if (c.supplyCap == 0 || c.borrowCap == 0 || c.accountDebtCap == 0) revert BadConfig();
        if (c.priorityUtilBps > BPS || (c.priorityUtilBps != 0 && c.priorityMinAge == 0)) revert BadConfig();
        if (cols.length == 0 || cols.length > MAX_COLLATERALS) revert BadConfig();

        registry = IChogAccountRegistry(registry_);
        loanToken = IERC20(c.loanToken);
        oracle = IPriceOracle(c.oracle);
        closeFactorBps = c.closeFactorBps;
        dustDebt = c.dustDebt;
        supplyCap = c.supplyCap;
        borrowCap = c.borrowCap;
        accountDebtCap = c.accountDebtCap;
        priorityUtilBps = c.priorityUtilBps;
        priorityMinAge = c.priorityMinAge;
        baseRateBps = c.baseRateBps;
        slope1Bps = c.slope1Bps;
        slope2Bps = c.slope2Bps;
        optimalUtilBps = c.optimalUtilBps;
        lastAccrual = uint64(block.timestamp);

        for (uint256 i; i < cols.length; ++i) {
            CollateralConfig memory cc = cols[i];
            if (cc.token == address(0) || cc.token == c.loanToken) revert BadConfig();
            // The vault must be able to hold it, otherwise the collateral could never be deposited.
            if (!IChogAccountRegistry(registry_).isTokenAllowed(cc.token)) revert BadConfig();
            if (cc.ltvBps == 0 || cc.ltvBps >= cc.liquidationThresholdBps || cc.liquidationThresholdBps > BPS) {
                revert BadConfig();
            }
            if (cc.liquidationBonusBps > 2_000 || cc.maxCounted == 0) revert BadConfig();
            // Aave-style solvency condition: threshold * (1 + bonus) <= 100%, so seizing value*(1+bonus) never exceeds
            // what the threshold implied was available.
            if (uint256(cc.liquidationThresholdBps) * (BPS + cc.liquidationBonusBps) > BPS * BPS) revert BadConfig();
            for (uint256 j; j < i; ++j) {
                if (cols[j].token == cc.token) revert BadConfig();
            }
            uint8 dec = IERC20Metadata(cc.token).decimals();
            if (dec > 36) revert BadConfig();
            _collaterals.push(
                Collateral(cc.token, dec, cc.ltvBps, cc.liquidationThresholdBps, cc.liquidationBonusBps, cc.maxCounted)
            );
        }

        positionManager = lp.positionManager;
        address lpFactory;
        if (lp.positionManager != address(0)) {
            lpFactory = INonfungiblePositionManager(lp.positionManager).factory();
            if (lpFactory == address(0)) revert BadConfig();
            _initLpPools(registry_, c.loanToken, lp.pools, lpFactory);
        } else if (lp.pools.length != 0) {
            revert BadConfig();
        }
        _lpFactory = lpFactory;
    }

    /// @dev Each LP pool must be the factory's genuine pool, hold only tokens the vault accepts, and hold only the loan
    ///      token or a configured collateral so that an unwound position can always be repaid from or seized.
    function _initLpPools(address registry_, address loan, LpPoolConfig[] memory pools, address lpFactory) private {
        if (pools.length == 0 || pools.length > MAX_LP_POOLS) revert BadConfig();
        for (uint256 i; i < pools.length; ++i) {
            LpPoolConfig memory p = pools[i];
            if (p.pool == address(0) || p.ltvBps == 0 || p.ltvBps >= p.liquidationThresholdBps) revert BadConfig();
            if (p.liquidationThresholdBps > BPS || p.liquidationBonusBps > 2_000) revert BadConfig();
            if (uint256(p.liquidationThresholdBps) * (BPS + p.liquidationBonusBps) > BPS * BPS) revert BadConfig();
            if (p.maxCountedValue == 0 || p.maxDeviationBps == 0 || p.maxDeviationBps > 1_000) revert BadConfig();
            for (uint256 j; j < i; ++j) {
                if (pools[j].pool == p.pool) revert BadConfig();
            }
            address t0 = IUniswapV3PoolInfo(p.pool).token0();
            address t1 = IUniswapV3PoolInfo(p.pool).token1();
            uint24 fee = IUniswapV3PoolInfo(p.pool).fee();
            if (IUniswapV3Factory(lpFactory).getPool(t0, t1, fee) != p.pool) revert BadConfig();
            if (!_lpTokenUsable(registry_, loan, t0) || !_lpTokenUsable(registry_, loan, t1)) revert BadConfig();
            _lpPools.push(
                LpPool(
                    p.pool,
                    t0,
                    t1,
                    fee,
                    p.ltvBps,
                    p.liquidationThresholdBps,
                    p.liquidationBonusBps,
                    p.maxDeviationBps,
                    p.maxCountedValue
                )
            );
        }
    }

    function _lpTokenUsable(address registry_, address loan, address token) private view returns (bool) {
        if (!IChogAccountRegistry(registry_).isTokenAllowed(token)) return false;
        return token == loan || _isCollateral(token);
    }

    // ================================================================ views

    function collateralCount() external view returns (uint256) {
        return _collaterals.length;
    }

    function collateralAt(uint256 i) external view returns (Collateral memory) {
        return _collaterals[i];
    }

    function availableLiquidity() public view returns (uint256) {
        return loanToken.balanceOf(address(this));
    }

    function totalDebt() public view returns (uint256) {
        return Math.mulDiv(totalScaledDebt, _indexNow(), RAY);
    }

    function totalAssets() public view returns (uint256) {
        return availableLiquidity() + totalDebt();
    }

    function utilizationBps() public view returns (uint256) {
        return _utilization(availableLiquidity(), Math.mulDiv(totalScaledDebt, borrowIndex, RAY));
    }

    function borrowRateBps() public view returns (uint256) {
        return _rate(utilizationBps());
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return Math.mulDiv(assets, totalShares + VIRTUAL_SHARES, totalAssets() + 1);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, totalAssets() + 1, totalShares + VIRTUAL_SHARES);
    }

    /// @notice Shares `lender` can redeem right now given the cash actually in the pool.
    function maxRedeem(address lender) external view returns (uint256) {
        uint256 byCash = Math.mulDiv(availableLiquidity(), totalShares + VIRTUAL_SHARES, totalAssets() + 1);
        uint256 owned = sharesOf[lender];
        return owned < byCash ? owned : byCash;
    }

    function debtOf(bytes32 key) public view returns (uint256) {
        return _debtFromScaled(debtScaled[key], _indexNow());
    }

    function lpPoolCount() external view returns (uint256) {
        return _lpPools.length;
    }

    function lpPoolAt(uint256 i) external view returns (LpPool memory) {
        return _lpPools[i];
    }

    /// @notice Raw (uncapped) oracle value of one position, for UIs. `ok == false` means it cannot be priced now.
    function positionValue(uint256 tokenId) external view returns (bool ok, uint256 value) {
        if (positionManager == address(0)) return (false, 0);
        (ok,, value) = _positionValue(tokenId);
    }

    /// @inheritdoc IPositionHost
    function positionAccepted(uint256 tokenId) external view returns (bool) {
        if (positionManager == address(0)) return false;
        (bool ok, PositionData memory p) = _readPosition(tokenId);
        if (!ok) return false;
        (bool found,,) = _lpPoolOf(p);
        return found;
    }

    /// @inheritdoc IPositionHost
    function positionWithdrawAllowed(bytes32 key, uint256 tokenId) external view returns (bool) {
        uint256 scaled = debtScaled[key];
        if (scaled == 0) return true; // no debt: never needs a price
        Valuation memory v = _valuationFull(key, address(0), 0, tokenId);
        return v.ok && _debtFromScaled(scaled, _indexNow()) <= v.borrowPower;
    }

    /// @inheritdoc ICreditModule
    function hasPendingOperation(bytes32) external pure returns (bool) {
        return false; // every action here is atomic
    }

    /// @inheritdoc ICreditModule
    function withdrawAllowed(bytes32 key, address token, uint256 amount) external view returns (bool) {
        uint256 scaled = debtScaled[key];
        if (scaled == 0) return true; // no debt: never needs a price
        if (!_isCollateral(token)) return true; // does not back the loan
        Valuation memory v = _valuation(key, token, amount);
        return v.ok && _debtFromScaled(scaled, _indexNow()) <= v.borrowPower;
    }

    /// @notice Everything a UI needs for one account; never reverts on an oracle problem (check `priceOk`).
    function accountData(bytes32 key) external view returns (AccountData memory d) {
        d.debt = debtOf(key);
        Valuation memory v = _valuation(key, address(0), 0);
        d.priceOk = v.ok;
        if (!v.ok) {
            d.healthFactorBps = d.debt == 0 ? type(uint256).max : 0;
            return d;
        }
        d.collateralValue = v.collateralValue;
        d.borrowPower = v.borrowPower;
        d.liquidationValue = v.liquidationValue;
        d.healthFactorBps = d.debt == 0 ? type(uint256).max : Math.mulDiv(v.liquidationValue, BPS, d.debt);
        d.availableToBorrow = _min(
            _min(_roomUnder(debtScaled[key], v.borrowPower), availableLiquidity()),
            _min(_roomUnder(debtScaled[key], accountDebtCap), _roomUnder(totalScaledDebt, borrowCap))
        );
    }

    // ================================================================ lenders

    function supply(uint256 assets) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        _accrue();
        uint256 ta = _totalAssetsStored();
        if (ta + assets > supplyCap) revert SupplyCapExceeded(ta + assets, supplyCap);
        shares = Math.mulDiv(assets, totalShares + VIRTUAL_SHARES, ta + 1);
        if (shares == 0) revert ZeroShares();

        _pull(msg.sender, assets);
        totalShares += shares;
        sharesOf[msg.sender] += shares;
        emit Supplied(msg.sender, assets, shares);
    }

    function redeem(uint256 shares) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        uint256 owned = sharesOf[msg.sender];
        if (shares > owned) revert InsufficientShares(shares, owned);
        _accrue();
        assets = Math.mulDiv(shares, _totalAssetsStored() + 1, totalShares + VIRTUAL_SHARES);
        if (assets == 0) revert ZeroAmount();
        uint256 cash = availableLiquidity();
        if (assets > cash) revert InsufficientLiquidity(assets, cash);

        sharesOf[msg.sender] = owned - shares;
        totalShares -= shares;
        loanToken.safeTransfer(msg.sender, assets);
        emit Redeemed(msg.sender, shares, assets);
    }

    // ================================================================ borrowers

    /// @dev When the pool would be busier than `priorityUtilBps` after this borrow, only vaults open for at least
    ///      `priorityMinAge` may borrow. It allocates scarce lending capacity; it never changes a limit or a rate.
    function _requirePriority(bytes32 key, uint256 poolDebtAfter, uint256 cashAfter) internal view {
        if (priorityUtilBps == 0) return;
        uint256 total = poolDebtAfter + cashAfter;
        uint256 util = total == 0 ? 0 : Math.mulDiv(poolDebtAfter, BPS, total);
        if (util <= priorityUtilBps) return;
        uint256 age = block.timestamp - registry.accountInfo(key).createdAt;
        if (age < priorityMinAge) revert PriorityAccessOnly(util, priorityMinAge, age);
    }

    /// @notice For UIs: would a vault of this age be held back from borrowing `amount` right now? (Uses the last accrued index.)
    function priorityRestricted(bytes32 key, uint256 amount) external view returns (bool) {
        if (priorityUtilBps == 0) return false;
        uint256 cash = availableLiquidity();
        if (amount > cash) return false; // a different error will say so
        uint256 debtAfter = Math.mulDiv(totalScaledDebt, borrowIndex, RAY) + amount;
        uint256 total = debtAfter + (cash - amount);
        uint256 util = total == 0 ? 0 : Math.mulDiv(debtAfter, BPS, total);
        if (util <= priorityUtilBps) return false;
        return block.timestamp - registry.accountInfo(key).createdAt < priorityMinAge;
    }

    /// @notice Borrow to your own wallet against the collateral in this account's vault. Only the account's
    ///         controller, and only while its Chog is escrowed.
    function borrow(bytes32 key, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!registry.isController(key, msg.sender)) revert NotController();
        if (!registry.canAcceptAssets(key)) revert NotEscrowed();
        _accrue();

        uint256 cash = availableLiquidity();
        if (amount > cash) revert InsufficientLiquidity(amount, cash);
        // Check the debt that will actually be STORED (scaled amount rounded up, then converted back rounding up),
        // not debtBefore + amount: the two can differ by one base unit once the index has moved.
        uint256 add = Math.mulDiv(amount, RAY, borrowIndex, Math.Rounding.Ceil);
        uint256 debtAfter = _debtFromScaled(debtScaled[key] + add, borrowIndex);
        uint256 poolAfter = _debtFromScaled(totalScaledDebt + add, borrowIndex);
        if (poolAfter > borrowCap) revert BorrowCapExceeded(poolAfter, borrowCap);
        if (debtAfter > accountDebtCap) revert AccountCapExceeded(debtAfter, accountDebtCap);
        _requirePriority(key, poolAfter, cash - amount);

        Valuation memory v = _valuation(key, address(0), 0);
        if (!v.ok) revert OracleFailure();
        if (debtAfter > v.borrowPower) revert BorrowLimitExceeded(debtAfter, v.borrowPower);

        debtScaled[key] += add;
        totalScaledDebt += add;
        loanToken.safeTransfer(msg.sender, amount);
        emit Borrowed(key, msg.sender, amount, _debtFromScaled(debtScaled[key], borrowIndex));
    }

    /// @notice Anyone may repay any account. Repays at most the outstanding debt; returns what was taken.
    function repay(bytes32 key, uint256 amount) external nonReentrant returns (uint256 repaid) {
        if (amount == 0) revert ZeroAmount();
        _accrue();
        uint256 debt = _debtFromScaled(debtScaled[key], borrowIndex);
        if (debt == 0) revert NoDebt();
        repaid = amount < debt ? amount : debt;
        _reduceDebt(key, repaid, debt);
        _pull(msg.sender, repaid);
        emit Repaid(key, msg.sender, repaid, _debtFromScaled(debtScaled[key], borrowIndex));
    }

    // ================================================================ liquidation

    /// @notice Anyone may repay part of an unhealthy account's debt and receive collateral worth the repayment plus the
    ///         liquidation bonus. Needs a working price. If this takes the last of the collateral and debt remains,
    ///         the remainder is written off against lenders.
    function liquidate(bytes32 key, uint256 repayAmount) external nonReentrant returns (uint256 repaid) {
        if (repayAmount == 0) revert ZeroAmount();
        _accrue();
        uint256 debt = _debtFromScaled(debtScaled[key], borrowIndex);
        if (debt == 0) revert NoDebt();
        _requireLiquidatable(key, debt);

        address vault = registry.accountInfo(key).vault;
        if (positionManager != address(0) && AccountVault(vault).positionCount() != 0) {
            // Positions are turned into plain tokens first; the loan-token share of the proceeds repays the debt at no
            // bonus. If that already restores health the call ends here and the liquidator pays nothing.
            debt = _unwindPositions(key, vault, debt);
            if (debt == 0) return 0;
            Valuation memory after_ = _valuation(key, address(0), 0);
            if (!after_.ok) revert OracleFailure();
            if (debt <= after_.liquidationValue) return 0;
        }
        (uint256 actual, uint256[4] memory seize, bool allSeized) =
            _planSeizure(vault, _min(repayAmount, _maxLiquidationRepay(debt)));
        if (actual == 0) revert NothingToSeize();
        _applyLiquidation(key, vault, debt, actual, seize, allSeized);
        return actual;
    }

    /// @dev Removes all liquidity from the account's positions, then applies the vault's loan-token balance (the
    ///      loan-token half of the proceeds) to the debt. Returns the debt that remains.
    function _unwindPositions(bytes32 key, address vault, uint256 debt) internal returns (uint256) {
        AccountVault v = AccountVault(vault);
        uint256 n = v.positionCount();
        for (uint256 i; i < n; ++i) {
            v.unwindPosition(v.positionAt(i));
        }
        uint256 bal = v.accounted(address(loanToken));
        uint256 take = _min(bal, debt);
        if (take != 0) {
            uint256 beforeBal = availableLiquidity();
            v.seizeCollateral(address(loanToken), take, address(this));
            uint256 got = availableLiquidity() - beforeBal;
            if (got != take) revert BalanceDeltaMismatch(take, got);
            _reduceDebt(key, take, debt);
        }
        emit PositionsUnwound(key, n, take);
        return _debtFromScaled(debtScaled[key], borrowIndex);
    }

    function _requireLiquidatable(bytes32 key, uint256 debt) internal view {
        Valuation memory v = _valuation(key, address(0), 0);
        if (!v.ok) revert OracleFailure();
        if (debt <= v.liquidationValue) revert NotLiquidatable(debt, v.liquidationValue);
    }

    function _maxLiquidationRepay(uint256 debt) internal view returns (uint256) {
        return debt <= dustDebt ? debt : Math.mulDiv(debt, closeFactorBps, BPS, Math.Rounding.Ceil);
    }

    /// @dev State first (debt, write-off), then the liquidator pays, then collateral moves.
    function _applyLiquidation(
        bytes32 key,
        address vault,
        uint256 debt,
        uint256 actual,
        uint256[4] memory seize,
        bool allSeized
    ) internal {
        _reduceDebt(key, actual, debt);
        if (allSeized) {
            uint256 left = _debtFromScaled(debtScaled[key], borrowIndex);
            if (left != 0) {
                totalScaledDebt -= debtScaled[key];
                debtScaled[key] = 0;
                emit BadDebtWrittenOff(key, left);
            }
        }
        _pull(msg.sender, actual);
        for (uint256 i; i < _collaterals.length; ++i) {
            if (seize[i] != 0) AccountVault(vault).seizeCollateral(_collaterals[i].token, seize[i], msg.sender);
        }
        emit Liquidated(key, msg.sender, actual, _debtFromScaled(debtScaled[key], borrowIndex));
    }

    // ================================================================ internals

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Largest `amount` for which `borrow` keeps stored debt at or below `limit`. Stored debt is
    ///      ceil(scaled * index / RAY) and the scaled amount added is ceil(amount * RAY / index), so the largest total
    ///      scaled balance that stays under `limit` is floor(limit * RAY / index); the room is whatever fits between
    ///      that and the current scaled balance, converted back and rounded down. Exact for any index, so a UI can
    ///      always borrow the figure it shows.
    function _roomUnder(uint256 scaledNow, uint256 limit) internal view returns (uint256) {
        uint256 idx = _indexNow();
        uint256 maxScaled = Math.mulDiv(limit, RAY, idx);
        if (maxScaled <= scaledNow) return 0;
        return Math.mulDiv(maxScaled - scaledNow, idx, RAY);
    }

    function _isCollateral(address token) internal view returns (bool) {
        for (uint256 i; i < _collaterals.length; ++i) {
            if (_collaterals[i].token == token) return true;
        }
        return false;
    }

    function _debtFromScaled(uint256 scaled, uint256 index) internal pure returns (uint256) {
        return Math.mulDiv(scaled, index, RAY, Math.Rounding.Ceil); // debt rounds up
    }

    function _totalAssetsStored() internal view returns (uint256) {
        return availableLiquidity() + Math.mulDiv(totalScaledDebt, borrowIndex, RAY); // lender claims round down
    }

    function _utilization(uint256 cash, uint256 debt) internal pure returns (uint256) {
        uint256 total = cash + debt;
        return total == 0 ? 0 : Math.mulDiv(debt, BPS, total);
    }

    function _rate(uint256 util) internal view returns (uint256) {
        if (util <= optimalUtilBps) return baseRateBps + (uint256(slope1Bps) * util) / optimalUtilBps;
        return baseRateBps + slope1Bps + (uint256(slope2Bps) * (util - optimalUtilBps)) / (BPS - optimalUtilBps);
    }

    function _indexNow() internal view returns (uint256) {
        uint256 dt = block.timestamp - lastAccrual;
        if (dt == 0 || totalScaledDebt == 0) return borrowIndex;
        uint256 rate = _rate(utilizationBps());
        return borrowIndex + Math.mulDiv(borrowIndex, rate * dt, BPS * YEAR);
    }

    function _accrue() internal {
        uint256 dt = block.timestamp - lastAccrual;
        if (dt == 0) return;
        if (totalScaledDebt != 0) {
            uint256 rate = _rate(utilizationBps());
            borrowIndex += Math.mulDiv(borrowIndex, rate * dt, BPS * YEAR);
            emit Accrued(borrowIndex, rate);
        }
        lastAccrual = uint64(block.timestamp);
    }

    /// @dev Reduce an account's debt by `amount` (<= `debt`). Paying the whole debt clears the scaled balance exactly.
    function _reduceDebt(bytes32 key, uint256 amount, uint256 debt) internal {
        uint256 scaled = debtScaled[key];
        uint256 cut = amount >= debt ? scaled : Math.mulDiv(amount, RAY, borrowIndex); // partial: round down
        if (cut > scaled) cut = scaled;
        debtScaled[key] = scaled - cut;
        totalScaledDebt -= cut;
    }

    function _pull(address from, uint256 amount) internal {
        uint256 beforeBal = availableLiquidity();
        loanToken.safeTransferFrom(from, address(this), amount);
        uint256 got = availableLiquidity() - beforeBal;
        if (got != amount) revert BalanceDeltaMismatch(amount, got);
    }

    function _tryQuote(address token, uint256 amount) internal view returns (bool ok, uint256 value) {
        try oracle.quote(token, amount) returns (uint256 r) {
            return (true, r);
        } catch {
            return (false, 0);
        }
    }

    function _valuation(bytes32 key, address hypToken, uint256 hypReduce) internal view returns (Valuation memory v) {
        return _valuationFull(key, hypToken, hypReduce, 0);
    }

    /// @dev `hypPosition` (a position token id, never 0) is treated as already gone from the vault.
    function _valuationFull(bytes32 key, address hypToken, uint256 hypReduce, uint256 hypPosition)
        internal
        view
        returns (Valuation memory v)
    {
        address vault = registry.accountInfo(key).vault;
        v.ok = true;
        for (uint256 i; i < _collaterals.length; ++i) {
            Collateral memory c = _collaterals[i];
            uint256 bal = AccountVault(vault).accounted(c.token);
            if (c.token == hypToken) {
                if (hypReduce > bal) return Valuation(false, 0, 0, 0);
                bal -= hypReduce;
            }
            // Only up to maxCounted units count: bounds the market impact of liquidating any single account.
            bal = _min(bal, c.maxCounted);
            if (bal == 0) continue;
            (bool ok, uint256 val) = _tryQuote(c.token, bal);
            if (!ok) return Valuation(false, 0, 0, 0);
            v.collateralValue += val;
            v.borrowPower += (val * c.ltvBps) / BPS;
            v.liquidationValue += (val * c.thresholdBps) / BPS;
        }
        if (positionManager == address(0)) return v;
        if (!_addPositions(vault, hypPosition, v)) return Valuation(false, 0, 0, 0);
    }

    /// @dev Adds every held position's counted value to `v`. Returns false (fail closed) if any cannot be priced.
    function _addPositions(address vault, uint256 hypPosition, Valuation memory v) internal view returns (bool) {
        uint256 n = AccountVault(vault).positionCount();
        if (n == 0) return true;
        uint256[2] memory perPool; // MAX_LP_POOLS entries: raw value held in each configured pool
        for (uint256 i; i < n; ++i) {
            uint256 id = AccountVault(vault).positionAt(i);
            if (id == hypPosition) continue;
            (bool ok, uint256 idx, uint256 val) = _positionValue(id);
            if (!ok) return false;
            perPool[idx] += val;
        }
        for (uint256 j; j < _lpPools.length; ++j) {
            if (perPool[j] == 0) continue;
            LpPool storage lp = _lpPools[j];
            uint256 counted = _min(perPool[j], lp.maxCountedValue);
            v.collateralValue += counted;
            v.borrowPower += (counted * lp.ltvBps) / BPS;
            v.liquidationValue += (counted * lp.thresholdBps) / BPS;
        }
        return true;
    }

    struct PositionData {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    /// @dev Reads a position without a 12-value decode. False if the call fails, the reply is the wrong size or the
    ///      ticks are out of range.
    function _readPosition(uint256 tokenId) internal view returns (bool ok, PositionData memory p) {
        (bool success, bytes memory ret) =
            positionManager.staticcall(abi.encodeCall(INonfungiblePositionManager.positions, (tokenId)));
        if (!success || ret.length != 12 * 32) return (false, p);
        uint256 w0;
        uint256 w1;
        uint256 fee;
        int256 tl;
        int256 tu;
        uint256 liq;
        assembly ("memory-safe") {
            w0 := mload(add(ret, 0x60)) // word 2: token0
            w1 := mload(add(ret, 0x80)) // word 3: token1
            fee := mload(add(ret, 0xa0)) // word 4
            tl := mload(add(ret, 0xc0)) // word 5
            tu := mload(add(ret, 0xe0)) // word 6
            liq := mload(add(ret, 0x100)) // word 7
        }
        if (w0 > type(uint160).max || w1 > type(uint160).max || fee > type(uint24).max) return (false, p);
        if (liq > type(uint128).max) return (false, p);
        int256 maxTick = int256(LpMath.MAX_TICK);
        if (tl < -maxTick || tu > maxTick || tl >= tu) return (false, p);
        p = PositionData(address(uint160(w0)), address(uint160(w1)), uint24(fee), int24(tl), int24(tu), uint128(liq));
        ok = true;
    }

    /// @dev Index of the configured pool a position belongs to; `found == false` if it is not in a whitelisted pool.
    function _lpPoolOf(PositionData memory p) internal view returns (bool found, uint256 idx, address poolAddr) {
        try IUniswapV3Factory(_lpFactory).getPool(p.token0, p.token1, p.fee) returns (address a) {
            poolAddr = a;
        } catch {
            return (false, 0, address(0));
        }
        if (poolAddr == address(0)) return (false, 0, address(0));
        for (uint256 i; i < _lpPools.length; ++i) {
            if (_lpPools[i].pool == poolAddr) return (true, i, poolAddr);
        }
    }

    /// @dev Value of one position at the ORACLE price, or ok == false if anything about it cannot be trusted.
    function _positionValue(uint256 tokenId) internal view returns (bool ok, uint256 idx, uint256 value) {
        PositionData memory p;
        (ok, p) = _readPosition(tokenId);
        if (!ok) return (false, 0, 0);
        address poolAddr;
        (ok, idx, poolAddr) = _lpPoolOf(p);
        if (!ok) return (false, 0, 0);
        if (p.liquidity == 0) return (true, idx, 0); // nothing to price
        uint160 sqrtOracle;
        (ok, sqrtOracle) = _oracleSqrtPrice(p.token0, p.token1);
        if (!ok) return (false, 0, 0);
        if (!_poolPriceAgrees(poolAddr, sqrtOracle, _lpPools[idx].maxDeviationBps)) return (false, 0, 0);
        (uint256 a0, uint256 a1) = LpMath.amountsForLiquidity(
            sqrtOracle, LpMath.sqrtRatioAtTick(p.tickLower), LpMath.sqrtRatioAtTick(p.tickUpper), p.liquidity
        );
        uint256 v0;
        uint256 v1;
        if (a0 != 0) {
            (ok, v0) = _tryQuote(p.token0, a0);
            if (!ok) return (false, 0, 0);
        }
        if (a1 != 0) {
            (ok, v1) = _tryQuote(p.token1, a1);
            if (!ok) return (false, 0, 0);
        }
        return (true, idx, v0 + v1);
    }

    /// @dev Price of token0 in token1 (as a Q64.96 square root) implied by the oracle, probed with a large quantity so
    ///      the integer loan-token values keep enough digits.
    function _oracleSqrtPrice(address t0, address t1) internal view returns (bool ok, uint160 sqrtP) {
        uint256 s0 = 10 ** IERC20Metadata(t0).decimals() * LP_QUOTE_WHOLE_TOKENS;
        uint256 s1 = 10 ** IERC20Metadata(t1).decimals() * LP_QUOTE_WHOLE_TOKENS;
        uint256 v0;
        uint256 v1;
        (ok, v0) = _tryQuote(t0, s0);
        if (!ok) return (false, 0);
        (ok, v1) = _tryQuote(t1, s1);
        if (!ok) return (false, 0);
        return LpMath.trySqrtPriceFromValues(v0, s0, v1, s1);
    }

    function _poolPriceAgrees(address poolAddr, uint160 sqrtOracle, uint16 maxBps) internal view returns (bool) {
        try IUniswapV3PoolState(poolAddr).slot0() returns (
            uint160 sqrtPool, int24, uint16, uint16, uint16, uint8, bool
        ) {
            if (sqrtPool < LpMath.MIN_SQRT_RATIO) {
                return false;
            }
            return LpMath.deviationBps(sqrtOracle, sqrtPool) <= maxBps;
        } catch {
            return false;
        }
    }

    /// @dev Decide how much collateral covers `target` of repayment plus each token's bonus, walking the configured
    ///      collaterals in order. Amounts round down in the borrower's favour. Reverts if a needed price is missing.
    function _planSeizure(address vault, uint256 target)
        internal
        view
        returns (uint256 actual, uint256[4] memory seize, bool allSeized)
    {
        uint256 remaining = target;
        allSeized = true;
        for (uint256 i; i < _collaterals.length; ++i) {
            uint256 bal = AccountVault(vault).accounted(_collaterals[i].token);
            if (bal == 0) continue;
            if (remaining == 0) {
                allSeized = false;
                continue;
            }
            (uint256 amt, uint256 left) = _seizeOne(_collaterals[i], bal, remaining);
            seize[i] = amt;
            remaining = left;
            if (amt < bal) allSeized = false;
        }
        actual = target - remaining;
    }

    /// @dev One token's share of a liquidation: returns the amount to take and the repayment still to cover.
    function _seizeOne(Collateral memory c, uint256 bal, uint256 remaining)
        internal
        view
        returns (uint256 amt, uint256 left)
    {
        uint256 value = oracle.quote(c.token, bal);
        uint256 need = Math.mulDiv(remaining, BPS + c.bonusBps, BPS);
        if (value >= need) {
            uint256 unit = oracle.quote(c.token, 10 ** c.decimals);
            if (unit == 0) revert OracleFailure();
            amt = _min(Math.mulDiv(need, 10 ** c.decimals, unit), bal);
            left = 0;
        } else {
            amt = bal;
            left = remaining - _min(Math.mulDiv(value, BPS, BPS + c.bonusBps), remaining);
        }
    }
}
