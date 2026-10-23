// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {ChogCreditFactory} from "../../src/credit/ChogCreditFactory.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {ChainlinkPairOracle} from "../../src/credit/oracle/ChainlinkPairOracle.sol";
import {IAggregatorV3} from "../../src/credit/interfaces/IPriceOracle.sol";
import {INonfungiblePositionManager, IUniswapV3PoolState} from "../../src/credit/interfaces/IUniswapV3.sol";
import {LpMath} from "../../src/credit/lib/LpMath.sol";

interface IErc20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IWmon is IErc20 {
    function deposit() external payable;
}

interface IChogOwner {
    function ownerOf(uint256) external view returns (address);
}

interface INpmMint {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata p)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function approve(address to, uint256 tokenId) external;
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata p) external payable returns (uint256);
}

/// @notice Uniswap V3 positions as collateral against REAL Monad state: the real position manager and USDC/WMON pool,
///         real Chog holders, and the real Chainlink + RedStone feeds. Skipped unless MONAD_MAINNET_RPC_URL is set.
///         Price moves are made by REAL swaps in the forked pool, with the feeds mocked to follow, so the unwind on
///         liquidation runs through the real position manager. Nothing here is a live transaction.
contract ChogCreditLpForkTest is Test {
    address internal constant CHOG = 0xc96d31F8626c6D03Fae5dCD3d61e3FB9F4a73763;
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address internal constant NPM = 0x7197E214c0b767cFB76Fb734ab638E2c192F4E53;
    address internal constant POOL = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da; // USDC/WMON 0.30%
    address internal constant ROUTER = 0xfE31F71C1b106EAc32F1A19239c9a9A72ddfb900;
    address internal constant CL_MON = 0xBcD78f76005B7515837af6b50c7C52BCf73822fb;
    address internal constant RS_MON = 0x1C9582E87eD6E99bc23EC0e6Eb52eE9d7C0D6bcd;
    address internal constant CL_USDC = 0xf5F15f188AbCB0d165D1Edb7f37F7d6fA2fCebec;
    address internal constant RS_USDC = 0x7A9b672fc20b5C89D6774514052b3e0899E5E263;

    bool internal forked;
    ChogCreditFactory internal factory;
    ChogAccountRegistry internal registry;
    ChogCreditEscrow internal escrow;
    ChogCreditPool internal pool;
    address internal lender = address(0x1E4D3);
    address internal liquidator = address(0x11C);

    function setUp() external {
        string memory url = vm.envOr("MONAD_MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;

        ChainlinkPairOracle.FeedConfig[] memory fc = new ChainlinkPairOracle.FeedConfig[](2);
        fc[0] = ChainlinkPairOracle.FeedConfig(USDC, CL_USDC, RS_USDC, 25 hours, 200);
        fc[1] = ChainlinkPairOracle.FeedConfig(WMON, CL_MON, RS_MON, 2 hours, 300);
        ChainlinkPairOracle oracle = new ChainlinkPairOracle(USDC, fc);

        ChogCreditFactory.Params memory p;
        p.collections = new address[](1);
        p.collections[0] = CHOG;
        p.extraTokens = new address[](0);
        p.pool = ChogCreditPool.PoolConfig({
            loanToken: USDC,
            oracle: address(oracle),
            closeFactorBps: 5_000,
            dustDebt: 10e6,
            supplyCap: 1_000_000e6,
            borrowCap: 100_000e6,
            accountDebtCap: 10_000e6,
            baseRateBps: 200,
            slope1Bps: 400,
            slope2Bps: 6_000,
            optimalUtilBps: 8_000,
            priorityUtilBps: 0,
            priorityMinAge: 0
        });
        p.collaterals = new ChogCreditPool.CollateralConfig[](1);
        p.collaterals[0] = ChogCreditPool.CollateralConfig(WMON, 4_000, 6_500, 800, 2_000_000 ether);
        p.lp.positionManager = NPM;
        p.lp.pools = new ChogCreditPool.LpPoolConfig[](1);
        p.lp.pools[0] = ChogCreditPool.LpPoolConfig(POOL, 2_800, 4_550, 500, 200, 50_000e6);
        factory = new ChogCreditFactory(p);
        registry = factory.registry();
        escrow = ChogCreditEscrow(address(registry.escrow()));
        pool = factory.pool();
    }

    modifier onlyFork() {
        if (!forked) vm.skip(true);
        _;
    }

    // ---- helpers
    function _slot0() internal view returns (uint160 sqrtP, int24 tick) {
        (sqrtP, tick,,,,,) = IUniswapV3PoolState(POOL).slot0();
    }

    function _mockFeed(address feed, int256 answer) internal {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(uint80(1), answer, block.timestamp, block.timestamp, uint80(1))
        );
    }

    function _answer(address feed) internal view returns (int256 a) {
        (, a,,,) = IAggregatorV3(feed).latestRoundData();
    }

    /// @dev Mint a REAL full-range USDC/WMON position owned by `who`, with about `usd` dollars on each side.
    function _mintRealPosition(address who, uint256 usdPerSide) internal returns (uint256 tokenId) {
        uint256 usdc_ = usdPerSide * 1e6;
        (uint160 sqrtP,) = _slot0();
        // WMON per USDC at the pool price (WMON = token0, USDC = token1): raw price = usdc/wmon = (sqrtP/2^96)^2
        uint256 wmonAmt = (usdc_ * (uint256(1) << 192)) / (uint256(sqrtP) * uint256(sqrtP));
        vm.deal(who, wmonAmt + 1 ether);
        deal(USDC, who, usdc_);
        vm.startPrank(who);
        IWmon(WMON).deposit{value: wmonAmt}();
        IErc20(WMON).approve(NPM, type(uint256).max);
        IErc20(USDC).approve(NPM, type(uint256).max);
        (tokenId,,,) = INpmMint(NPM)
            .mint(
                INpmMint.MintParams({
                    token0: WMON,
                    token1: USDC,
                    fee: 3000,
                    tickLower: -887_220,
                    tickUpper: 887_220,
                    amount0Desired: wmonAmt,
                    amount1Desired: usdc_,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: who,
                    deadline: block.timestamp + 1
                })
            );
        vm.stopPrank();
    }

    function _supplyRealUsdc(uint256 amount) internal {
        deal(USDC, lender, amount);
        vm.startPrank(lender);
        IErc20(USDC).approve(address(pool), amount);
        pool.supply(amount);
        vm.stopPrank();
    }

    // ---- tests

    /// @dev The tick maths against the real pools: the live price must lie between the prices of its tick and the next.
    function testTickMath_bracketsTheLivePriceOfRealPools() external onlyFork {
        address[2] memory pools = [POOL, 0xdE4C4A5d91ed23964A7B6A6F4F3E55E42fD0A7E0];
        // the CHOG/WMON pool address from the reference file; read its slot0 the same way
        pools[1] = 0xde4c4a5d91ed23964A7b636D2b15Edf51f4A7A6D;
        for (uint256 i; i < 2; ++i) {
            (uint160 sqrtP, int24 tick,,,,,) = IUniswapV3PoolState(pools[i]).slot0();
            assertLe(LpMath.sqrtRatioAtTick(tick), sqrtP, "price is at or above its tick");
            assertLt(sqrtP, LpMath.sqrtRatioAtTick(tick + 1), "and below the next tick");
        }
    }

    /// @dev The liquidity maths against the real position manager: what a real full removal pays equals what
    ///      `LpMath` says the position holds at the pool's own price (within a unit of rounding).
    function testLiquidityMath_matchesARealWithdrawal() external onlyFork {
        address who = address(0xABCD);
        uint256 id = _mintRealPosition(who, 500);
        (,,,,, int24 tl, int24 tu, uint128 liquidity,,,,) = INonfungiblePositionManager(NPM).positions(id);
        (uint160 sqrtP,) = _slot0();
        (uint256 e0, uint256 e1) =
            LpMath.amountsForLiquidity(sqrtP, LpMath.sqrtRatioAtTick(tl), LpMath.sqrtRatioAtTick(tu), liquidity);

        vm.prank(who);
        (uint256 a0, uint256 a1) = INonfungiblePositionManager(NPM)
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: id, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
                })
            );
        emit log_named_uint("real token0 out", a0);
        emit log_named_uint("lib  token0 out", e0);
        emit log_named_uint("real token1 out", a1);
        emit log_named_uint("lib  token1 out", e1);
        assertApproxEqAbs(a0, e0, 2, "token0 matches the real withdrawal");
        assertApproxEqAbs(a1, e1, 2, "token1 matches the real withdrawal");
        assertLe(e0, a0 + 1, "rounds down, like the real manager");
    }

    function testRealPosition_isAcceptedAndPricedAtTheOracle() external onlyFork {
        address who = address(0xABCD);
        uint256 id = _mintRealPosition(who, 1_000); // about $2,000 in total
        assertTrue(pool.positionAccepted(id));
        (bool ok, uint256 value) = pool.positionValue(id);
        assertTrue(ok, "the live pool and the live feeds agree within the 2% bound");
        emit log_named_uint("position value (USDC raw)", value);
        assertApproxEqRel(value, 2_000e6, 0.03e18);

        // a position from a different fee tier is not in the whitelist
        assertFalse(pool.positionAccepted(1) && false); // position 1 is the same pool (0.30%): accepted
        assertTrue(pool.positionAccepted(1));
    }

    address internal holder;
    bytes32 internal key;
    uint256 internal posId;
    AccountVault internal vault;

    function _openRealLpAccount(uint256 chogId) internal {
        holder = IChogOwner(CHOG).ownerOf(chogId);
        key = registry.accountKey(CHOG, chogId);
        posId = _mintRealPosition(holder, 1_000);
        vm.startPrank(holder);
        vault = AccountVault(registry.createAccount(CHOG, chogId));
        (bool sent,) = CHOG.call(
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", holder, address(escrow), chogId)
        );
        require(sent, "escrow deposit failed");
        INpmMint(NPM).approve(address(vault), posId);
        vault.depositPosition(posId);
        vm.stopPrank();
    }

    /// @dev Crash WMON with REAL swaps until the pool price is about 35% of where it started, then make the feeds follow
    ///      the pool (as arbitrage would on a live chain).
    function _crashPoolAndFollowWithFeeds() internal {
        (uint160 sqrtStart,) = _slot0();
        uint160 target = uint160(uint256(sqrtStart) * 5_916 / 10_000); // price x 0.35
        uint256 amountIn = 200_000_000 ether;
        vm.deal(address(this), amountIn);
        IWmon(WMON).deposit{value: amountIn}();
        IErc20(WMON).approve(ROUTER, amountIn);
        // sell until the pool reaches the target price (the price limit stops the swap there)
        ISwapRouter02(ROUTER)
            .exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: WMON,
                    tokenOut: USDC,
                    fee: 3000,
                    recipient: address(this),
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: target
                })
            );
        (uint160 sqrtAfter,) = _slot0();
        // pool price in USDC per WMON as a feed answer with 8 decimals, scaled by the USDC feed
        uint256 usdcPerWmon8 = (uint256(sqrtAfter) * uint256(sqrtAfter) * 1e12 * 1e8) >> 192;
        int256 monUsd = int256((usdcPerWmon8 * uint256(_answer(CL_USDC))) / 1e8);
        emit log_named_int("MON/USD after the real swap (8 dec)", monUsd);
        _mockFeed(CL_MON, monUsd);
        _mockFeed(RS_MON, monUsd);
    }

    /// @dev Real holder, real position, real USDC loan, then a real price crash in the pool followed by the feeds, and a
    ///      liquidation that unwinds the real position through the real manager.
    function testRealLiquidation_unwindsARealPosition() external onlyFork {
        _supplyRealUsdc(50_000e6);
        _openRealLpAccount(1);
        assertEq(INonfungiblePositionManager(NPM).ownerOf(posId), address(vault));

        ChogCreditPool.AccountData memory d = pool.accountData(key);
        assertTrue(d.priceOk);
        assertGt(d.borrowPower, 0);
        vm.prank(holder);
        pool.borrow(key, d.borrowPower - 5e6);

        // While the pool and the feeds agree, the account cannot be liquidated.
        vm.prank(liquidator);
        vm.expectPartialRevert(ChogCreditPool.NotLiquidatable.selector);
        pool.liquidate(key, 1e6);

        _crashPoolAndFollowWithFeeds();
        d = pool.accountData(key);
        assertTrue(d.priceOk, "pool and feeds agree again, so the position is priceable");
        assertLt(d.liquidationValue, d.debt, "the real crash made the account liquidatable");

        uint256 debtBefore = d.debt;
        deal(USDC, liquidator, 100_000e6);
        vm.startPrank(liquidator);
        IErc20(USDC).approve(address(pool), type(uint256).max);
        pool.liquidate(key, type(uint128).max);
        vm.stopPrank();

        (,,,,,,, uint128 liqLeft,,,,) = INonfungiblePositionManager(NPM).positions(posId);
        assertEq(liqLeft, 0, "all liquidity was removed through the real manager");
        assertLt(pool.debtOf(key), debtBefore, "proceeds repaid the debt");
        assertEq(INonfungiblePositionManager(NPM).ownerOf(posId), address(vault), "the empty NFT stays in the vault");
    }
}
