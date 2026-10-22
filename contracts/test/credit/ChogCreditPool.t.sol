// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {ChogCreditFactory} from "../../src/credit/ChogCreditFactory.sol";
import {IChogAccountRegistry, ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {FeeOnTransferToken} from "../../src/mocks/HostileMocks.sol";

contract ChogCreditPoolTest is CreditBase {
    // ======================================================================== wiring
    function test_factoryBindsPoolOnce_andHasNoOtherPower() external {
        assertEq(registry.creditModule(), address(pool));
        assertEq(registry.binder(), address(factory));
        vm.expectRevert(IChogAccountRegistry.ModuleAlreadyBound.selector);
        vm.prank(address(factory));
        registry.bindCreditModule(address(0xBEEF));
        // nobody else could ever have bound it
        vm.expectRevert(IChogAccountRegistry.NotBinder.selector);
        registry.bindCreditModule(address(0xBEEF));
        assertEq(address(pool.registry()), address(registry));
    }

    function test_collateralTokensAreAutomaticallyVaultAllowed() external view {
        assertTrue(registry.isTokenAllowed(address(wmon)));
        assertFalse(registry.isTokenAllowed(address(btc)));
    }

    function test_constructorValidation() external {
        ChogCreditPool.PoolConfig memory c = _poolConfig();
        ChogCreditPool.CollateralConfig[] memory cols = _collaterals(false);
        address r = address(registry);

        ChogCreditPool.PoolConfig memory bad = _poolConfig();
        bad.closeFactorBps = 0;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.closeFactorBps = 10_001;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.optimalUtilBps = 0;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.optimalUtilBps = 10_000;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.slope2Bps = 60_000;
        bad.slope1Bps = 40_000;
        bad.baseRateBps = 1;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.supplyCap = 0;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, bad, cols);
        bad = _poolConfig();
        bad.oracle = address(0);
        vm.expectRevert(ChogCreditPool.ZeroAddress.selector);
        new ChogCreditPool(r, bad, cols);
        vm.expectRevert(ChogCreditPool.ZeroAddress.selector);
        new ChogCreditPool(address(0), c, cols);

        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, new ChogCreditPool.CollateralConfig[](0));
        ChogCreditPool.CollateralConfig[] memory five = new ChogCreditPool.CollateralConfig[](5);
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, five);
    }

    function test_constructorValidation_collateral() external {
        ChogCreditPool.PoolConfig memory c = _poolConfig();
        address r = address(registry);
        ChogCreditPool.CollateralConfig[] memory one = new ChogCreditPool.CollateralConfig[](1);

        one[0] = ChogCreditPool.CollateralConfig(address(wmon), 7_500, 7_500, 500); // ltv == threshold
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);
        one[0] = ChogCreditPool.CollateralConfig(address(wmon), 5_000, 9_600, 500); // threshold * (1+bonus) > 100%
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);
        one[0] = ChogCreditPool.CollateralConfig(address(wmon), 5_000, 7_500, 2_001); // bonus too large
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);
        one[0] = ChogCreditPool.CollateralConfig(address(wmon), 0, 7_500, 500); // zero ltv
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);
        one[0] = ChogCreditPool.CollateralConfig(address(usdc), 5_000, 7_500, 500); // loan token as collateral
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);
        one[0] = ChogCreditPool.CollateralConfig(address(btc), 5_000, 7_500, 500); // vault would reject it
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, one);

        ChogCreditPool.CollateralConfig[] memory dup = new ChogCreditPool.CollateralConfig[](2);
        dup[0] = ChogCreditPool.CollateralConfig(address(wmon), 5_000, 7_500, 500);
        dup[1] = dup[0];
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditPool(r, c, dup);
    }

    // ======================================================================== lenders
    function test_supplyAndRedeem_roundTrip() external {
        uint256 shares = _supply(lender, 10_000 * USDC);
        assertEq(shares, 10_000 * USDC * 1e6, "first deposit gets assets * virtual shares");
        assertEq(pool.totalAssets(), 10_000 * USDC);
        assertEq(pool.convertToAssets(shares), 10_000 * USDC - 0); // virtual offset costs at most a wei
        vm.prank(lender);
        uint256 out = pool.redeem(shares);
        assertGe(out, 10_000 * USDC - 1);
        assertEq(usdc.balanceOf(lender), out);
        assertEq(pool.totalShares(), 0);
    }

    function test_supply_zeroCapAndShareChecks() external {
        vm.expectRevert(ChogCreditPool.ZeroAmount.selector);
        pool.supply(0);
        _supply(lender, 1_000_000 * USDC);
        deal(address(usdc), lender2, 1);
        vm.startPrank(lender2);
        usdc.approve(address(pool), 1);
        vm.expectRevert(
            abi.encodeWithSelector(ChogCreditPool.SupplyCapExceeded.selector, 1_000_000 * USDC + 1, 1_000_000 * USDC)
        );
        pool.supply(1);
        vm.stopPrank();
    }

    function test_redeem_checks() external {
        _supply(lender, 1_000 * USDC);
        vm.startPrank(lender);
        vm.expectRevert(ChogCreditPool.ZeroAmount.selector);
        pool.redeem(0);
        uint256 owned = pool.sharesOf(lender);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.InsufficientShares.selector, owned + 1, owned));
        pool.redeem(owned + 1);
        vm.stopPrank();
    }

    function test_inflationAttack_victimIsNotRobbed() external {
        // attacker deposits 1 wei, then donates a large amount straight to the pool to skew the share price
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.supplyCap = type(uint128).max;
        _deploy(pc, _collaterals(false));
        address attacker = address(0xA77);
        _supply(attacker, 1);
        deal(address(usdc), address(pool), usdc.balanceOf(address(pool)) + 1_000_000 * USDC); // the donation
        uint256 victimShares = _supply(lender, 1_000_000 * USDC);
        assertGt(victimShares, 0, "victim must still receive shares");
        vm.prank(lender);
        uint256 out = pool.redeem(victimShares);
        // share-granularity rounding costs the victim well under one part in a million
        assertGe(out, 1_000_000 * USDC - 1 * USDC, "victim recovers essentially everything");
        // and the attacker is the one who loses: they get back far less than they donated
        uint256 attackerShares = pool.sharesOf(attacker);
        vm.prank(attacker);
        uint256 attackerOut = pool.redeem(attackerShares);
        assertLt(attackerOut, 600_000 * USDC, "the attack is unprofitable");
    }

    function test_failsClosedOnFeeOnTransferLoanToken() external {
        FeeOnTransferToken fee = new FeeOnTransferToken();
        oracle.setPrice(address(wmon), 2e18); // priced in the 18-decimal fee token
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.loanToken = address(fee);
        pc.dustDebt = 10e18;
        pc.supplyCap = type(uint128).max;
        pc.borrowCap = type(uint128).max;
        pc.accountDebtCap = type(uint128).max;
        _deploy(pc, _collaterals(false));
        fee.mint(lender, 1_000e18);
        vm.startPrank(lender);
        fee.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.BalanceDeltaMismatch.selector, 100e18, 99e18));
        pool.supply(100e18);
        vm.stopPrank();
    }

    function test_redeem_limitedByCash_thenAvailableAfterRepay() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 10_000 * WMON); // power 10,000 USDC
        _borrow(alice, 1, 9_000 * USDC);
        uint256 all = pool.sharesOf(lender);
        assertLt(pool.maxRedeem(lender), all, "cash is lower than the lender's claim");
        uint256 claim = pool.convertToAssets(all);
        uint256 cash = usdc.balanceOf(address(pool));
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.InsufficientLiquidity.selector, claim, cash));
        pool.redeem(all);
        // redeem what cash allows
        uint256 part = pool.maxRedeem(lender);
        vm.prank(lender);
        pool.redeem(part);
        assertLe(usdc.balanceOf(address(pool)), 1);
    }

    function test_interestRaisesSharePrice_andIsSharedProRata() external {
        uint256 s1 = _supply(lender, 6_000 * USDC);
        uint256 s2 = _supply(lender2, 4_000 * USDC);
        _fund(alice, 1, 2_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        uint256 before = pool.totalAssets();
        vm.warp(block.timestamp + 365 days);
        assertGt(pool.totalAssets(), before, "interest accrues to lenders");
        uint256 a1 = pool.convertToAssets(s1);
        uint256 a2 = pool.convertToAssets(s2);
        assertApproxEqRel(a1 * 4, a2 * 6, 1e12, "6:4 split preserved");
        assertGt(a1 + a2, 10_000 * USDC);
    }

    // ======================================================================== borrow
    function test_borrow_toWallet_atExactLimit_andOneWeiOver() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ChogCreditPool.BorrowLimitExceeded.selector, 1_000 * USDC + 1, 1_000 * USDC)
        );
        pool.borrow(k, 1_000 * USDC + 1);

        vm.prank(alice);
        pool.borrow(k, 1_000 * USDC);
        assertEq(usdc.balanceOf(alice), 1_000 * USDC, "proceeds go to the borrower's wallet");
        assertEq(usdc.balanceOf(registry.vaultOf(address(chog), 1)), 0, "never into the vault");
        assertEq(pool.debtOf(k), 1_000 * USDC);
        assertEq(registry.debtOf(k), 1_000 * USDC);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ChogCreditPool.BorrowLimitExceeded.selector, 1_000 * USDC + 1, 1_000 * USDC)
        );
        pool.borrow(k, 1);
    }

    function test_borrow_authorization() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(bob);
        vm.expectRevert(ChogCreditPool.NotController.selector);
        pool.borrow(k, 1);

        // a wallet-held (not escrowed) account cannot borrow even for its owner
        vm.prank(alice);
        registry.createAccount(address(chog), 2);
        bytes32 k2 = _key(2);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.NotEscrowed.selector);
        pool.borrow(k2, 1);

        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.ZeroAmount.selector);
        pool.borrow(k, 0);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.NotController.selector);
        pool.borrow(bytes32(uint256(99)), 1); // unknown account
    }

    function test_borrow_limitsCashCapsAndOracle() external {
        _supply(lender, 500 * USDC);
        _fund(alice, 1, 10_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.InsufficientLiquidity.selector, 501 * USDC, 500 * USDC));
        pool.borrow(k, 501 * USDC);

        oracle.setDown(true);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1 * USDC);
        oracle.setDown(false);
    }

    function test_borrow_accountAndPoolCaps() external {
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.accountDebtCap = 300 * USDC;
        pc.borrowCap = 400 * USDC;
        _deploy(pc, _collaterals(false));
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 10_000 * WMON);
        _fund(alice, 2, 10_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.AccountCapExceeded.selector, 301 * USDC, 300 * USDC));
        pool.borrow(k, 301 * USDC);
        _borrow(alice, 1, 300 * USDC);
        bytes32 k2 = _key(2);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.BorrowCapExceeded.selector, 401 * USDC, 400 * USDC));
        pool.borrow(k2, 101 * USDC);
    }

    function test_accountData_reportsPowerHealthAndRoom() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertTrue(d.priceOk);
        assertEq(d.collateralValue, 2_000 * USDC);
        assertEq(d.borrowPower, 1_000 * USDC);
        assertEq(d.liquidationValue, 1_500 * USDC);
        assertEq(d.healthFactorBps, type(uint256).max);
        assertEq(d.availableToBorrow, 1_000 * USDC);

        _borrow(alice, 1, 600 * USDC);
        d = pool.accountData(k);
        assertEq(d.debt, 600 * USDC);
        assertEq(d.healthFactorBps, 25_000); // 1500 / 600
        assertEq(d.availableToBorrow, 400 * USDC);

        oracle.setDown(true);
        d = pool.accountData(k);
        assertFalse(d.priceOk, "a price outage is reported, not thrown");
        assertEq(d.debt, 600 * USDC);
    }

    /// @dev Regression: found by the invariant suite. After interest has moved the index, borrowing exactly the
    ///      headroom used to leave the stored debt one base unit above borrowing power.
    function test_borrowingTheReportedRoom_neverLeavesDebtAbovePower() external {
        _supply(lender, 1_000_000 * USDC);
        _fund(alice, 1, 100_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 50_000 * USDC + 3);
        vm.warp(block.timestamp + 37 days + 12345);
        deal(address(usdc), address(this), 1);
        usdc.approve(address(pool), 1);
        pool.repay(k, 1); // accrue so the index is not a round number
        uint256 room = pool.accountData(k).availableToBorrow;
        assertGt(room, 0);
        vm.prank(alice);
        pool.borrow(k, room);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertLe(d.debt, d.borrowPower);
        // and one more unit is refused
        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(k, 2);
    }

    function testFuzz_reportedRoomIsAlwaysBorrowable(uint32 secs, uint96 first) external {
        _supply(lender, 1_000_000 * USDC);
        _fund(alice, 1, 100_000 * WMON);
        bytes32 k = _key(1);
        first = uint96(bound(first, 1, 90_000 * USDC));
        _borrow(alice, 1, first);
        vm.warp(block.timestamp + bound(secs, 1, 400 days));
        deal(address(usdc), address(this), 1);
        usdc.approve(address(pool), 1);
        pool.repay(k, 1);
        uint256 room = pool.accountData(k).availableToBorrow;
        if (room == 0) return;
        vm.prank(alice);
        pool.borrow(k, room);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertLe(d.debt, d.borrowPower);
    }

    /// @dev Pins the rounding direction: stored debt is the exact value rounded UP, never down.
    function test_debtRoundsUp_neverDown() external {
        _supply(lender, 1_000_000 * USDC);
        _fund(alice, 1, 100_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 12_345_678_901);
        vm.warp(block.timestamp + 11 days + 4_321);
        deal(address(usdc), address(this), 1);
        usdc.approve(address(pool), 1);
        pool.repay(k, 1); // accrue
        uint256 scaled = pool.debtScaled(k);
        uint256 idx = pool.borrowIndex();
        uint256 floorDebt = scaled * idx / 1e27;
        assertTrue(scaled * idx % 1e27 != 0, "test must hit a fractional case");
        assertEq(pool.debtOf(k), floorDebt + 1, "debt is rounded up");
    }

    /// @dev Regression for the 1-wei overshoot: borrowing the NAIVE headroom (power - debt) must either revert or leave
    ///      debt within power. Without the fix it succeeded and left debt one unit over.
    function test_borrowingTheNaiveHeadroom_neverOvershoots() external {
        _supply(lender, 1_000_000 * USDC);
        _fund(alice, 1, 100_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 50_000 * USDC + 3);
        vm.warp(block.timestamp + 37 days + 12345);
        deal(address(usdc), address(this), 1);
        usdc.approve(address(pool), 1);
        pool.repay(k, 1);
        ChogCreditPool.AccountData memory d0 = pool.accountData(k);
        uint256 naive = d0.borrowPower - d0.debt;
        vm.prank(alice);
        try pool.borrow(k, naive) {} catch {}
        ChogCreditPool.AccountData memory d1 = pool.accountData(k);
        assertLe(d1.debt, d1.borrowPower, "debt must never exceed borrowing power");
        assertLe(d0.availableToBorrow, naive, "never above the naive headroom");
        assertGe(d0.availableToBorrow + 3, naive, "and not materially below it");
    }

    /// @dev The pool-wide borrow cap must also hold exactly, in stored (rounded-up) terms, when it is the binding limit.
    function testFuzz_poolBorrowCapHoldsExactly_whenItIsTheBindingLimit(uint32 secs, uint96 first) external {
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.borrowCap = 50_000 * USDC;
        _deploy(pc, _collaterals(false));
        _supply(lender, 900_000 * USDC);
        _fund(alice, 1, 500_000 * WMON);
        bytes32 k = _key(1);
        first = uint96(bound(first, 1, 30_000 * USDC));
        _borrow(alice, 1, first);
        vm.warp(block.timestamp + bound(secs, 1, 300 days));
        deal(address(usdc), address(this), 1);
        usdc.approve(address(pool), 1);
        pool.repay(k, 1); // accrue so the index is not a round number
        uint256 room = pool.accountData(k).availableToBorrow;
        if (room == 0) return;
        vm.prank(alice);
        pool.borrow(k, room);
        // now push past the room: whether each attempt reverts or succeeds, the cap must still hold in STORED terms,
        // which is what the check inside borrow() is responsible for
        for (uint256 extra = 1; extra <= 3; extra++) {
            vm.prank(alice);
            try pool.borrow(k, extra) {} catch {}
            uint256 storedTotal = Math.mulDiv(pool.totalScaledDebt(), pool.borrowIndex(), 1e27, Math.Rounding.Ceil);
            assertLe(storedTotal, pc.borrowCap, "stored pool debt must not exceed the cap");
        }
    }

    // ======================================================================== interest
    function test_interest_exactOneYearAtTenPercentUtilization() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        assertEq(pool.utilizationBps(), 1_000);
        assertEq(pool.borrowRateBps(), 250); // 200 + 400 * 1000 / 8000
        vm.warp(block.timestamp + 365 days);
        assertEq(pool.debtOf(_key(1)), 1_025 * USDC);
        assertEq(registry.debtOf(_key(1)), 1_025 * USDC, "the registry reports the same figure");
    }

    function test_rateModel_kink() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 10_000 * WMON);
        _borrow(alice, 1, 8_000 * USDC);
        assertEq(pool.utilizationBps(), 8_000);
        assertEq(pool.borrowRateBps(), 600); // 200 + 400
        _borrow(alice, 1, 1_000 * USDC);
        assertEq(pool.utilizationBps(), 9_000);
        assertEq(pool.borrowRateBps(), 3_600); // 600 + 6000 * (9000-8000)/2000
    }

    function test_interest_isNotLostBetweenAccrualCalls() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        uint256 t0 = block.timestamp;
        // poke the pool many times; the view at the end must match a single-step accrual closely
        for (uint256 i = 1; i <= 12; i++) {
            vm.warp(t0 + i * 30 days);
            deal(address(usdc), address(this), 1);
            usdc.approve(address(pool), 1);
            pool.repay(_key(1), 1);
        }
        uint256 stepped = pool.debtOf(_key(1));
        assertGt(stepped, 1_000 * USDC);
        assertLt(stepped, 1_030 * USDC);
    }

    // ======================================================================== repay
    function test_repay_partialFullOverpayAndThirdParty() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 500 * USDC);
        bytes32 k = _key(1);

        deal(address(usdc), bob, 1_000 * USDC);
        vm.startPrank(bob); // a stranger can repay
        usdc.approve(address(pool), type(uint256).max);
        assertEq(pool.repay(k, 200 * USDC), 200 * USDC);
        assertEq(pool.debtOf(k), 300 * USDC);
        uint256 before = usdc.balanceOf(bob);
        assertEq(pool.repay(k, 10_000 * USDC), 300 * USDC, "overpayment takes only the debt");
        assertEq(before - usdc.balanceOf(bob), 300 * USDC);
        vm.stopPrank();
        assertEq(pool.debtOf(k), 0);
        assertEq(pool.debtScaled(k), 0);
        assertEq(pool.totalScaledDebt(), 0);

        vm.expectRevert(ChogCreditPool.NoDebt.selector);
        pool.repay(k, 1);
        vm.expectRevert(ChogCreditPool.ZeroAmount.selector);
        pool.repay(k, 0);
    }

    function test_repay_worksDuringOracleOutage() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 500 * USDC);
        oracle.setDown(true);
        deal(address(usdc), alice, 500 * USDC);
        bytes32 k = _key(1);
        vm.startPrank(alice);
        usdc.approve(address(pool), 500 * USDC);
        pool.repay(k, 500 * USDC);
        vm.stopPrank();
        assertEq(pool.debtOf(k), 0);
    }

    // ======================================================================== withdrawing collateral
    function test_withdraw_withinLimit_andBeyond() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 500 * USDC); // needs >= 500 power => >= 500 WMON... 1 WMON = 2 USDC at 50% => 1 USDC power
        // keep 500 WMON (power 500): can withdraw exactly 500
        vm.startPrank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawERC20(address(wmon), 500 * WMON + 1, alice);
        v.withdrawERC20(address(wmon), 500 * WMON, alice);
        vm.stopPrank();
        assertEq(v.accounted(address(wmon)), 500 * WMON);
        // and now nothing more
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawERC20(address(wmon), 1, alice);
    }

    function test_withdraw_debtFree_neverNeedsAPrice() external {
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        oracle.setDown(true);
        // a PARTIAL withdrawal leaves collateral that would need pricing if the pool bothered to look
        vm.startPrank(alice);
        v.withdrawERC20(address(wmon), 400 * WMON, alice);
        v.withdrawERC20(address(wmon), 600 * WMON, alice);
        vm.stopPrank();
        assertTrue(v.isEmpty());
    }

    function test_withdraw_whileIndebted_failsClosedOnOracleOutage() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 100 * USDC);
        oracle.setDown(true);
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawERC20(address(wmon), 1 * WMON, alice);
    }

    function test_withdraw_nonCollateralTokenIsUnaffectedByDebt() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC); // at the limit
        // a token that does not back the loan can always be withdrawn, even with debt at the limit
        assertTrue(pool.withdrawAllowed(_key(1), address(0x1234), 1));
        // while the collateral token cannot move at all
        assertFalse(pool.withdrawAllowed(_key(1), address(wmon), 1));
    }

    function test_borrowThenReleaseFlow() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 400 * USDC);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.ReleaseBlocked.selector, k, ReleaseBlocker.HasAssets));
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();

        deal(address(usdc), alice, 400 * USDC);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, 400 * USDC);
        v.withdrawERC20(address(wmon), 1_000 * WMON, alice);
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), alice);
    }

    function test_liabilityBlockerReportsDebt() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 1_000 * USDC);
        assertEq(uint8(registry.liabilityBlocker(k)), uint8(ReleaseBlocker.HasDebt));
    }

    // ======================================================================== liquidation
    function _crashTo(uint256 priceRaw) internal {
        oracle.setPrice(address(wmon), priceRaw);
    }

    function test_liquidate_healthyReverts() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        bytes32 k = _key(1);
        deal(address(usdc), liquidator, 100 * USDC);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.NotLiquidatable.selector, 1_000 * USDC, 1_500 * USDC));
        pool.liquidate(k, 100 * USDC);
        vm.stopPrank();
    }

    function test_liquidate_thresholdBoundary() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        bytes32 k = _key(1);
        _crashTo(1_333_333); // liquidation value = 1000 * 1.333333 * 0.75 = 999.99975 < 1000 debt => liquidatable
        assertLt(pool.accountData(k).healthFactorBps, 10_000);
        _crashTo(1_333_334); // 1000.0005 > 1000 => healthy
        assertGe(pool.accountData(k).healthFactorBps, 10_000);
        deal(address(usdc), liquidator, 10 * USDC);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.liquidate(k, 10 * USDC);
        vm.stopPrank();
    }

    function test_liquidate_closeFactor_bonusAndExactSeizure() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        _crashTo(1_200_000); // 1 WMON = 1.2 USDC: value 1200, liquidation value 900 < debt 1000
        bytes32 k = _key(1);
        uint256 poolCashBefore = usdc.balanceOf(address(pool));

        uint256 repaid = _liquidate(liquidator, 1, 1_000 * USDC); // asks for everything
        assertEq(repaid, 500 * USDC, "close factor caps the repayment at 50%");
        assertEq(wmon.balanceOf(liquidator), 437_500000000000000000, "525 USDC of collateral at 1.2 = 437.5 WMON");
        assertEq(pool.debtOf(k), 500 * USDC);
        assertEq(usdc.balanceOf(address(pool)) - poolCashBefore, 500 * USDC);
        assertEq(AccountVault(registry.vaultOf(address(chog), 1)).accounted(address(wmon)), 562_500000000000000000);
        // the account is healthy again afterwards
        assertGe(pool.accountData(k).healthFactorBps, 10_000);
    }

    function test_liquidate_dustDebtCanBeClosedInFull() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 10 * WMON); // value 20, power 10
        _borrow(alice, 1, 10 * USDC); // exactly the dust threshold
        _crashTo(1_000_000); // value 10, liquidation value 7.5 < 10
        bytes32 k = _key(1);
        uint256 repaid = _liquidate(liquidator, 1, 10 * USDC);
        // need 10.5 USDC of collateral but only 10 exist => all collateral taken, repayment 10/1.05
        assertEq(repaid, 9_523_809);
        assertEq(wmon.balanceOf(liquidator), 10 * WMON);
        assertEq(pool.debtOf(k), 0, "the remainder is written off");
    }

    function test_liquidate_badDebt_isWrittenOffAgainstLenders() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        bytes32 k = _key(1);
        uint256 lenderClaimBefore = pool.convertToAssets(pool.sharesOf(lender));
        _crashTo(400_000); // collateral worth 400 against 1000 of debt
        uint256 repaid = _liquidate(liquidator, 1, 1_000 * USDC);

        assertEq(repaid, 380_952_380);
        assertEq(wmon.balanceOf(liquidator), 1_000 * WMON, "all collateral seized");
        assertEq(pool.debtOf(k), 0);
        assertEq(pool.debtScaled(k), 0);
        assertEq(pool.totalScaledDebt(), 0);
        assertEq(pool.totalAssets(), 9_000 * USDC + 380_952_380, "lenders absorb the shortfall");
        assertLt(pool.convertToAssets(pool.sharesOf(lender)), lenderClaimBefore);
    }

    function test_liquidate_worksWithMultipleCollateralsInOrder() external {
        _deploy(_poolConfig(), _collaterals(true));
        // btc must be vault-allowed: the factory adds every collateral token automatically
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 100 * WMON); // 200 USDC
        _deposit(alice, 1, address(btc), 1e6); // 0.01 BTC = 600 USDC
        // power = 100 + 420 = 520
        _borrow(alice, 1, 500 * USDC);
        _crashTo(500_000); // WMON -> 0.5 (value 50)
        oracle.setPrice(address(btc), 30_000 * USDC); // BTC value 300
        // liquidation value = 37.5 + 240 = 277.5 < 500
        uint256 repaid = _liquidate(liquidator, 1, 500 * USDC); // capped at 250
        assertGt(repaid, 0);
        assertEq(wmon.balanceOf(liquidator), 100 * WMON, "first collateral is taken first and entirely");
        assertGt(btc.balanceOf(liquidator), 0, "the remainder comes from the second");
        // total seized value ~ repaid * 1.05
        uint256 seizedValue = 50 * USDC + btc.balanceOf(liquidator) * 30_000 * USDC / 1e8;
        assertApproxEqAbs(seizedValue, repaid * 10_500 / 10_000, 2_000);
    }

    function test_liquidate_requiresPrice_andDebt() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        deal(address(usdc), liquidator, 10 * USDC);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.expectRevert(ChogCreditPool.NoDebt.selector);
        pool.liquidate(k, 1);
        vm.expectRevert(ChogCreditPool.ZeroAmount.selector);
        pool.liquidate(k, 0);
        vm.stopPrank();

        _borrow(alice, 1, 1_000 * USDC);
        _crashTo(1_000_000);
        oracle.setDown(true);
        vm.prank(liquidator);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.liquidate(k, 1);
    }

    function test_liquidation_voidsPendingSaleAcceptances() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 1_000 * USDC);
        uint256 nonceBefore = v.stateNonce();
        _crashTo(1_200_000);
        _liquidate(liquidator, 1, 1_000 * USDC);
        assertGt(v.stateNonce(), nonceBefore);
    }

    function test_liquidated_accountCanStillRepayAndExit() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 1_000 * USDC);
        _crashTo(1_200_000);
        _liquidate(liquidator, 1, 1_000 * USDC);
        _crashTo(2_000_000);
        uint256 debt = pool.debtOf(k);
        deal(address(usdc), alice, debt);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, debt);
        v.withdrawERC20(address(wmon), v.accounted(address(wmon)), alice);
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), alice);
    }

    // ======================================================================== misc
    function test_pendingOperationIsAlwaysFalse() external view {
        assertFalse(pool.hasPendingOperation(bytes32(uint256(1))));
    }

    function test_noAdminSurface() external {
        (bool ok,) = address(pool).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        (ok,) = address(pool).call(abi.encodeWithSignature("setOracle(address)", address(1)));
        assertFalse(ok);
        (ok,) = address(pool).call(abi.encodeWithSignature("pause()"));
        assertFalse(ok);
    }

    function testFuzz_borrowNeverExceedsPower(uint96 collateral, uint96 want) external {
        collateral = uint96(bound(collateral, 1 * WMON, 50_000 * WMON));
        _supply(lender, 900_000 * USDC);
        _fund(alice, 1, collateral);
        bytes32 k = _key(1);
        uint256 power = pool.accountData(k).borrowPower;
        want = uint96(bound(want, 1, 200_000 * USDC));
        vm.prank(alice);
        if (want > power || want > 100_000 * USDC) {
            vm.expectRevert();
            pool.borrow(k, want);
        } else {
            pool.borrow(k, want);
            assertLe(pool.debtOf(k), power);
        }
    }
}
