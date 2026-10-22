// SPDX-License-Identifier: MIT
// LEGACY (pre-v0.2 prototype): mints its own account NFT. Not the Chog Credit identity design. Replaced in Gate B-D.
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ChogPositionNFT} from "./ChogPositionNFT.sol";

/// @title Chog Credit MVP
/// @notice A deliberately narrow account-NFT-backed USDC lending facility for Monad testnet experiments.
/// @dev Collateral valuation is owner-administered. DO NOT deploy with real funds or to mainnet without a
///      production oracle, independent audit, risk review, liquidity accounting redesign, and operational controls.
contract ChogCredit is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 public constant LIQUIDATION_BONUS_BPS = 11_000; // 10% bonus to liquidator

    IERC20 public immutable usdc;
    IERC20 public immutable collateralToken;
    ChogPositionNFT public immutable positionNFT;
    uint8 public immutable collateralDecimals;

    // USDC base units per 1 whole collateral token. For 6-decimal USDC, $1.00 is 1_000_000.
    uint256 public collateralPriceUsdcPerToken;
    uint256 public maxLtvBps;
    uint256 public liquidationThresholdBps;
    uint256 public annualInterestRateBps;

    mapping(uint256 => uint256) public collateralOf;
    mapping(uint256 => uint256) private _debtPrincipal;
    mapping(uint256 => uint256) private _lastAccruedAt;
    // Remainder numerator preserves sub-base-unit interest across frequent interactions.
    mapping(uint256 => uint256) private _interestRemainder;
    mapping(address => uint256) public providerLiquidity;
    uint256 public totalOutstandingPrincipal;
    uint256 public totalLiquidityProvided;

    error InvalidAddress();
    error InvalidRiskParameters();
    error NotAccountOwner();
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error BorrowLimitExceeded(uint256 attemptedDebt, uint256 maxDebt);
    error DebtOutstanding(uint256 accountId, uint256 debt);
    error NoCollateral();
    error NotLiquidatable(uint256 accountId, uint256 debt, uint256 thresholdValue);
    error InvalidAmount();
    error OutstandingLoansBlockLiquidityWithdrawal();
    error InsufficientProviderBalance();

    event AccountCreated(uint256 indexed accountId, address indexed owner);
    event CollateralDeposited(uint256 indexed accountId, address indexed owner, uint256 amount);
    event CollateralWithdrawn(uint256 indexed accountId, address indexed owner, uint256 amount);
    event LiquidityProvided(address indexed provider, uint256 amount);
    event LiquidityWithdrawn(address indexed provider, uint256 amount);
    event Borrowed(uint256 indexed accountId, address indexed borrower, uint256 amount, uint256 totalDebt);
    event Repaid(uint256 indexed accountId, address indexed payer, uint256 amount, uint256 remainingDebt);
    event Liquidated(uint256 indexed accountId, address indexed liquidator, uint256 repaid, uint256 collateralSeized);
    event RiskParametersUpdated(
        uint256 price, uint256 maxLtvBps, uint256 liquidationThresholdBps, uint256 annualInterestRateBps
    );

    constructor(
        address usdcAddress,
        address collateralAddress,
        address positionNFTAddress,
        address initialOwner,
        uint256 initialCollateralPriceUsdcPerToken,
        uint256 initialMaxLtvBps,
        uint256 initialLiquidationThresholdBps,
        uint256 initialAnnualInterestRateBps
    ) Ownable(initialOwner) {
        if (
            usdcAddress == address(0) || collateralAddress == address(0) || positionNFTAddress == address(0)
                || initialOwner == address(0)
        ) revert InvalidAddress();
        uint8 decimals_ = IERC20MetadataLike(collateralAddress).decimals();
        if (decimals_ > 24) revert InvalidRiskParameters();
        usdc = IERC20(usdcAddress);
        collateralToken = IERC20(collateralAddress);
        positionNFT = ChogPositionNFT(positionNFTAddress);
        collateralDecimals = decimals_;
        _setRiskParameters(
            initialCollateralPriceUsdcPerToken,
            initialMaxLtvBps,
            initialLiquidationThresholdBps,
            initialAnnualInterestRateBps
        );
    }

    modifier onlyAccountOwner(uint256 accountId) {
        if (positionNFT.ownerOf(accountId) != msg.sender) revert NotAccountOwner();
        _;
    }

    /// @notice Create an account represented by a transferable NFT.
    function createAccount() external returns (uint256 accountId) {
        accountId = positionNFT.mint(msg.sender);
        emit AccountCreated(accountId, msg.sender);
    }

    /// @notice Supply USDC liquidity. There is no USDC minting: lenders must fund this pool.
    function provideLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        providerLiquidity[msg.sender] += amount;
        totalLiquidityProvided += amount;
        emit LiquidityProvided(msg.sender, amount);
    }

    /// @dev MVP safety rule: lender exits are allowed only after all borrower debt has been repaid.
    function withdrawLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (totalOutstandingPrincipal != 0) revert OutstandingLoansBlockLiquidityWithdrawal();
        if (providerLiquidity[msg.sender] < amount) revert InsufficientProviderBalance();
        providerLiquidity[msg.sender] -= amount;
        totalLiquidityProvided -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit LiquidityWithdrawn(msg.sender, amount);
    }

    function depositCollateral(uint256 accountId, uint256 amount) external onlyAccountOwner(accountId) nonReentrant {
        if (amount == 0) revert InvalidAmount();
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateralOf[accountId] += amount;
        emit CollateralDeposited(accountId, msg.sender, amount);
    }

    /// @notice Entire-collateral withdrawal only after debt is zero; avoids partial withdrawals undermining solvency.
    function withdrawCollateral(uint256 accountId, uint256 amount) external onlyAccountOwner(accountId) nonReentrant {
        if (amount == 0 || collateralOf[accountId] < amount) revert InvalidAmount();
        uint256 debt = debtOf(accountId);
        if (debt != 0) revert DebtOutstanding(accountId, debt);
        collateralOf[accountId] -= amount;
        collateralToken.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(accountId, msg.sender, amount);
    }

    function borrow(uint256 accountId, uint256 amount) external onlyAccountOwner(accountId) nonReentrant {
        if (amount == 0) revert InvalidAmount();
        _accrue(accountId);
        uint256 available = usdc.balanceOf(address(this));
        if (available < amount) revert InsufficientLiquidity(amount, available);
        uint256 attemptedDebt = _debtPrincipal[accountId] + amount;
        uint256 maxDebt = maxBorrowUsdc(accountId);
        if (attemptedDebt > maxDebt) revert BorrowLimitExceeded(attemptedDebt, maxDebt);
        _debtPrincipal[accountId] = attemptedDebt;
        totalOutstandingPrincipal += amount;
        if (_lastAccruedAt[accountId] == 0) _lastAccruedAt[accountId] = block.timestamp;
        usdc.safeTransfer(msg.sender, amount);
        emit Borrowed(accountId, msg.sender, amount, attemptedDebt);
    }

    function repay(uint256 accountId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        _accrue(accountId);
        uint256 debt = _debtPrincipal[accountId];
        uint256 amountToRepay = amount > debt ? debt : amount;
        if (amountToRepay == 0) revert InvalidAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amountToRepay);
        _debtPrincipal[accountId] = debt - amountToRepay;
        totalOutstandingPrincipal -= amountToRepay;
        if (_debtPrincipal[accountId] == 0) {
            _lastAccruedAt[accountId] = 0;
            _interestRemainder[accountId] = 0;
        }
        emit Repaid(accountId, msg.sender, amountToRepay, debt - amountToRepay);
    }

    /// @notice Permissionless liquidation when debt exceeds the configured fraction of marked collateral value.
    /// @dev Price is admin-managed in this MVP, so this is not safe for production deployment.
    function liquidate(uint256 accountId, uint256 requestedRepayAmount) external nonReentrant {
        if (requestedRepayAmount == 0) revert InvalidAmount();
        _accrue(accountId);
        uint256 debt = _debtPrincipal[accountId];
        uint256 value = collateralValueUsdc(accountId);
        uint256 thresholdValue = value * liquidationThresholdBps / BPS;
        if (debt <= thresholdValue) revert NotLiquidatable(accountId, debt, thresholdValue);
        uint256 repayAmount = requestedRepayAmount > debt ? debt : requestedRepayAmount;
        uint256 seizeValue = repayAmount * LIQUIDATION_BONUS_BPS / BPS;
        uint256 seizeAmount = seizeValue * (10 ** collateralDecimals) / collateralPriceUsdcPerToken;
        uint256 collateralBalance = collateralOf[accountId];
        if (seizeAmount > collateralBalance) seizeAmount = collateralBalance;
        if (seizeAmount == 0) revert NoCollateral();
        usdc.safeTransferFrom(msg.sender, address(this), repayAmount);
        _debtPrincipal[accountId] = debt - repayAmount;
        totalOutstandingPrincipal -= repayAmount;
        collateralOf[accountId] = collateralBalance - seizeAmount;
        if (_debtPrincipal[accountId] == 0) {
            _lastAccruedAt[accountId] = 0;
            _interestRemainder[accountId] = 0;
        }
        collateralToken.safeTransfer(msg.sender, seizeAmount);
        emit Liquidated(accountId, msg.sender, repayAmount, seizeAmount);
    }

    /// @notice Liquid cash presently available for new borrows.
    function availableLiquidity() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function debtOf(uint256 accountId) public view returns (uint256) {
        uint256 principal = _debtPrincipal[accountId];
        uint256 last = _lastAccruedAt[accountId];
        if (principal == 0 || last == 0 || block.timestamp <= last) return principal;
        uint256 numerator = principal * annualInterestRateBps * (block.timestamp - last) + _interestRemainder[accountId];
        uint256 interest = numerator / (BPS * YEAR);
        return principal + interest;
    }

    function collateralValueUsdc(uint256 accountId) public view returns (uint256) {
        return collateralOf[accountId] * collateralPriceUsdcPerToken / (10 ** collateralDecimals);
    }

    /// @notice Maximum total debt in USDC base units, not incremental borrowing capacity.
    function maxBorrowUsdc(uint256 accountId) public view returns (uint256) {
        return collateralValueUsdc(accountId) * maxLtvBps / BPS;
    }

    function availableBorrowUsdc(uint256 accountId) external view returns (uint256) {
        uint256 cap = maxBorrowUsdc(accountId);
        uint256 debt = debtOf(accountId);
        return cap > debt ? cap - debt : 0;
    }

    /// @notice Collateral/debt ratio in basis points. type(uint256).max indicates no debt.
    function healthFactorBps(uint256 accountId) external view returns (uint256) {
        uint256 debt = debtOf(accountId);
        if (debt == 0) return type(uint256).max;
        return collateralValueUsdc(accountId) * BPS / debt;
    }

    function setRiskParameters(
        uint256 priceUsdcPerToken,
        uint256 maxLtv,
        uint256 liquidationThreshold,
        uint256 annualRate
    ) external onlyOwner {
        _setRiskParameters(priceUsdcPerToken, maxLtv, liquidationThreshold, annualRate);
    }

    function _accrue(uint256 accountId) internal {
        uint256 last = _lastAccruedAt[accountId];
        uint256 principal = _debtPrincipal[accountId];
        if (principal == 0) {
            _lastAccruedAt[accountId] = block.timestamp;
            _interestRemainder[accountId] = 0;
            return;
        }
        if (last == 0) {
            _lastAccruedAt[accountId] = block.timestamp;
            return;
        }
        if (block.timestamp > last) {
            uint256 denominator = BPS * YEAR;
            uint256 numerator =
                principal * annualInterestRateBps * (block.timestamp - last) + _interestRemainder[accountId];
            uint256 interest = numerator / denominator;
            _interestRemainder[accountId] = numerator % denominator;
            if (interest > 0) {
                _debtPrincipal[accountId] = principal + interest;
                totalOutstandingPrincipal += interest;
            }
            _lastAccruedAt[accountId] = block.timestamp;
        }
    }

    function _setRiskParameters(uint256 price, uint256 maxLtv, uint256 liquidationThreshold, uint256 annualRate)
        internal
    {
        if (
            price == 0 || maxLtv == 0 || maxLtv >= liquidationThreshold || liquidationThreshold > BPS
                || annualRate > 3_000
        ) revert InvalidRiskParameters();
        collateralPriceUsdcPerToken = price;
        maxLtvBps = maxLtv;
        liquidationThresholdBps = liquidationThreshold;
        annualInterestRateBps = annualRate;
        emit RiskParametersUpdated(price, maxLtv, liquidationThreshold, annualRate);
    }
}

interface IERC20MetadataLike {
    function decimals() external view returns (uint8);
}
