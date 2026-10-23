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

interface IERC20Fork {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IWMON is IERC20Fork {
    function deposit() external payable;
}

interface IChogFork {
    function ownerOf(uint256) external view returns (address);
}

/// @notice The full credit system against REAL Monad mainnet state: real Chog Genesis holders, real Circle USDC, real
///         WMON and the real Chainlink + RedStone feeds. Skipped unless MONAD_MAINNET_RPC_URL is set. Price moves are
///         simulated with vm.mockCall on the feeds, so nothing here is a live transaction.
contract ChogCreditForkTest is Test {
    address internal constant CHOG = 0xc96d31F8626c6D03Fae5dCD3d61e3FB9F4a73763;
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address internal constant CL_MON = 0xBcD78f76005B7515837af6b50c7C52BCf73822fb;
    address internal constant RS_MON = 0x1C9582E87eD6E99bc23EC0e6Eb52eE9d7C0D6bcd;
    address internal constant CL_USDC = 0xf5F15f188AbCB0d165D1Edb7f37F7d6fA2fCebec;
    address internal constant RS_USDC = 0x7A9b672fc20b5C89D6774514052b3e0899E5E263;

    bool internal forked;
    ChogCreditFactory internal factory;
    ChogAccountRegistry internal registry;
    ChogCreditEscrow internal escrow;
    ChogCreditPool internal pool;
    ChainlinkPairOracle internal oracle;
    address internal lender = address(0x1E4D3);
    address internal liquidator = address(0x11C);
    address internal holder;
    bytes32 internal key;
    AccountVault internal vault;

    function setUp() external {
        string memory url = vm.envOr("MONAD_MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;

        // Feed bounds chosen for THIS test from observed ages only; real heartbeats are not verified (see docs).
        ChainlinkPairOracle.FeedConfig[] memory fc = new ChainlinkPairOracle.FeedConfig[](2);
        fc[0] = ChainlinkPairOracle.FeedConfig(USDC, CL_USDC, RS_USDC, 25 hours, 200);
        fc[1] = ChainlinkPairOracle.FeedConfig(WMON, CL_MON, RS_MON, 2 hours, 300);
        oracle = new ChainlinkPairOracle(USDC, fc);

        ChogCreditFactory.Params memory p;
        p.collections = new address[](1);
        p.collections[0] = CHOG;
        p.extraTokens = new address[](0);
        p.rescuer = address(0);
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
            optimalUtilBps: 8_000
        });
        p.collaterals = new ChogCreditPool.CollateralConfig[](1);
        p.collaterals[0] = ChogCreditPool.CollateralConfig(WMON, 4_000, 6_500, 800, 2_000_000 ether);
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
    function _mockFeed(address feed, int256 answer) internal {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(uint80(1), answer, block.timestamp, block.timestamp, uint80(1))
        );
    }

    function _currentAnswer(address feed) internal view returns (int256 a) {
        (, a,,,) = IAggregatorV3(feed).latestRoundData();
    }

    function _supplyRealUsdc(uint256 amount) internal {
        deal(USDC, lender, amount);
        vm.startPrank(lender);
        IERC20Fork(USDC).approve(address(pool), amount);
        pool.supply(amount);
        vm.stopPrank();
    }

    /// @dev Open, escrow and fund the REAL holder of Chog `id` with `wmonAmount` of real WMON (wrapped from native MON).
    function _openRealAccount(uint256 id, uint256 wmonAmount) internal {
        holder = IChogFork(CHOG).ownerOf(id);
        key = registry.accountKey(CHOG, id);
        vm.deal(holder, wmonAmount + 1 ether);
        vm.startPrank(holder);
        vault = AccountVault(registry.createAccount(CHOG, id));
        (bool ok,) =
            CHOG.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", holder, address(escrow), id));
        require(ok, "escrow deposit failed");
        IWMON(WMON).deposit{value: wmonAmount}();
        IWMON(WMON).approve(address(vault), wmonAmount);
        vault.depositERC20(WMON, wmonAmount);
        vm.stopPrank();
    }

    // ---- tests
    function testRealOracle_pricesWmonInUsdcSensibly() external onlyFork {
        uint256 v = oracle.quote(WMON, 1_000e18); // value of 1,000 MON in USDC raw units
        emit log_named_uint("1,000 WMON in USDC raw", v);
        // MON traded around $0.02 when written; accept a wide band so the test survives price drift but not unit errors
        assertGt(v, 1e6, "implausibly cheap: a decimals/scale error");
        assertLt(v, 500e6, "implausibly expensive: a decimals/scale error");
        // equals the lower of the two sources, converted through the USDC feeds
        int256 cl = _currentAnswer(CL_MON);
        int256 rs = _currentAnswer(RS_MON);
        int256 lo = cl < rs ? cl : rs;
        int256 uC = _currentAnswer(CL_USDC);
        int256 uR = _currentAnswer(RS_USDC);
        int256 uLo = uC < uR ? uC : uR;
        uint256 expected = uint256(lo) * 1_000e18 * 1e6 / (uint256(uLo) * 1e18);
        assertApproxEqRel(v, expected, 1e12, "matches the manual two-source computation");
    }

    function testRealFlow_lendBorrowRepayExit_forRealHolders() external onlyFork {
        _supplyRealUsdc(50_000e6);
        for (uint256 id = 1; id <= 2; id++) {
            // token 1 is a plain EOA, token 2 is an EIP-7702-delegated EOA
            _openRealAccount(id, 1_000_000e18); // ~$20k of WMON at ~$0.02
            ChogCreditPool.AccountData memory d = pool.accountData(key);
            assertTrue(d.priceOk);
            assertGt(d.borrowPower, 0);

            uint256 want = d.availableToBorrow < 2_000e6 ? d.availableToBorrow : 2_000e6;
            vm.prank(holder);
            pool.borrow(key, want);
            assertEq(IERC20Fork(USDC).balanceOf(holder), want, "real USDC paid to the real holder's wallet");
            assertEq(pool.debtOf(key), want);

            // collateral cannot be pulled while indebted beyond the limit
            vm.prank(holder);
            vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
            vault.withdrawERC20(WMON, 1_000_000e18, holder);

            vm.startPrank(holder);
            IERC20Fork(USDC).approve(address(pool), type(uint256).max);
            pool.repay(key, type(uint256).max);
            vault.withdrawERC20(WMON, 1_000_000e18, holder);
            escrow.release(CHOG, id, holder);
            vm.stopPrank();
            assertEq(IChogFork(CHOG).ownerOf(id), holder, "the real Chog is back with its holder");
            assertEq(pool.debtOf(key), 0);
        }
    }

    function testRealLiquidation_afterBothFeedsCrash() external onlyFork {
        _supplyRealUsdc(50_000e6);
        _openRealAccount(1, 1_000_000e18);
        uint256 room = pool.accountData(key).availableToBorrow;
        uint256 amt = room; // borrow to the limit so a 40% crash makes the account unhealthy
        vm.prank(holder);
        pool.borrow(key, amt);

        int256 cl = _currentAnswer(CL_MON);
        int256 rs = _currentAnswer(RS_MON);
        _mockFeed(CL_MON, cl * 60 / 100); // -40%: liquidation value falls below the debt (65% threshold)
        _mockFeed(RS_MON, rs * 60 / 100);

        ChogCreditPool.AccountData memory d = pool.accountData(key);
        assertTrue(d.priceOk);
        assertLt(d.healthFactorBps, 10_000, "unhealthy after the crash");

        deal(USDC, liquidator, 10_000e6);
        uint256 wmonBefore = IERC20Fork(WMON).balanceOf(liquidator);
        vm.startPrank(liquidator);
        IERC20Fork(USDC).approve(address(pool), type(uint256).max);
        uint256 repaid = pool.liquidate(key, 10_000e6);
        vm.stopPrank();
        assertLe(repaid, (amt + 1) / 2 + 1, "close factor respected");
        assertGt(IERC20Fork(WMON).balanceOf(liquidator) - wmonBefore, 0, "liquidator received real WMON");
    }

    function test_failsClosed_whenOnlyOneSourceMoves() external onlyFork {
        _supplyRealUsdc(50_000e6);
        _openRealAccount(1, 1_000_000e18);
        uint256 room = pool.accountData(key).availableToBorrow;
        vm.prank(holder);
        pool.borrow(key, room < 1_000e6 ? room : 1_000e6);

        // a crash seen by one feed only: the sources now disagree by far more than the bound
        _mockFeed(CL_MON, _currentAnswer(CL_MON) / 5);

        ChogCreditPool.AccountData memory d = pool.accountData(key);
        assertFalse(d.priceOk, "the pool refuses to value collateral when sources disagree");
        deal(USDC, liquidator, 1_000e6);
        vm.startPrank(liquidator);
        IERC20Fork(USDC).approve(address(pool), type(uint256).max);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.liquidate(key, 100e6);
        vm.stopPrank();

        // but the borrower can still repay and leave: nothing that reduces risk needs a price
        vm.startPrank(holder);
        deal(USDC, holder, 5_000e6);
        IERC20Fork(USDC).approve(address(pool), type(uint256).max);
        pool.repay(key, type(uint256).max);
        vault.withdrawERC20(WMON, 1_000_000e18, holder);
        vm.stopPrank();
    }

    function testFeedOutage_blocksBorrowing_butNotRepayOrDebtFreeExit() external onlyFork {
        _supplyRealUsdc(50_000e6);
        _openRealAccount(1, 1_000_000e18);
        // debt-free partial withdrawal with the feed down must work
        vm.mockCallRevert(CL_MON, abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector), "feed down");
        vm.prank(holder);
        vault.withdrawERC20(WMON, 100_000e18, holder);
        // borrowing needs a price
        vm.prank(holder);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(key, 1e6);
        vm.clearMockedCalls();
    }
}
