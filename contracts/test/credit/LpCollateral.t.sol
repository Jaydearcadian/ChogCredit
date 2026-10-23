// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LpBase} from "./LpBase.sol";
import {CreditBase} from "./CreditBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {LpMath} from "../../src/credit/lib/LpMath.sol";
import {MockV3Pool, MockPositionManager} from "../../src/mocks/MockUniswapV3.sol";

/// @dev Uniswap V3 positions as collateral (docs/LP_COLLATERAL_SPEC.md).
contract LpCollateralTest is LpBase {
    function mkPool(
        address r,
        ChogCreditPool.PoolConfig memory c,
        ChogCreditPool.CollateralConfig[] memory cols,
        ChogCreditPool.LpConfig memory lp
    ) external returns (ChogCreditPool) {
        return new ChogCreditPool(r, c, cols, lp);
    }

    bytes32 internal k;
    AccountVault internal v;
    uint256 internal pos;

    function setUp() public override {
        super.setUp();
        _supply(lender, 100_000 * USDC);
    }

    function _alice1(uint128 liquidity) internal {
        pos = _openWithPosition(alice, 1, liquidity);
        v = AccountVault(registry.vaultOf(address(chog), 1));
        k = _key(1);
    }

    // ---------------------------------------------------------------- custody

    function test_deposit_makesTheVaultTheOwner_andNonEmpty() external {
        _alice1(L_2K);
        assertEq(pm.ownerOf(pos), address(v));
        assertEq(v.positionCount(), 1);
        assertEq(v.positionAt(0), pos);
        assertTrue(v.holdsPosition(pos));
        assertFalse(v.isEmpty());
        assertEq(v.positionManager(), address(pm));
        vm.prank(alice);
        vm.expectRevert(); // the Chog cannot leave while a position is inside
        escrow.release(address(chog), 1, alice);
    }

    function test_deposit_bumpsTheStateNonce() external {
        _openAccount(alice, 1);
        AccountVault vv = AccountVault(registry.vaultOf(address(chog), 1));
        uint256 id = _mint(alice, L_2K);
        uint256 n0 = vv.stateNonce();
        _depositPos(alice, 1, id);
        assertEq(vv.stateNonce(), n0 + 1);
    }

    function test_deposit_rules() external {
        _openAccount(alice, 1);
        AccountVault vv = AccountVault(registry.vaultOf(address(chog), 1));
        uint256 id = _mint(alice, L_2K);
        vm.startPrank(alice);
        pm.approve(address(vv), id);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(AccountVault.NotController.selector);
        vv.depositPosition(id);

        // a position from a pool that is not whitelisted
        address other = v3f.createPool(address(wmon), address(btc), 500);
        uint256 bad = pm.mint(alice, other, FULL_LO, FULL_HI, 1e12);
        vm.startPrank(alice);
        pm.approve(address(vv), bad);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.PositionNotAccepted.selector, bad));
        vv.depositPosition(bad);
        vm.stopPrank();

        // a burned / unknown id
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.PositionNotAccepted.selector, 999));
        vv.depositPosition(999);

        // a position the caller does not own cannot be pulled in
        uint256 bobs = _mint(bob, L_2K);
        vm.prank(alice);
        vm.expectRevert();
        vv.depositPosition(bobs);
    }

    function test_deposit_needsAnEscrowedChog() external {
        vm.prank(alice);
        AccountVault vv = AccountVault(registry.createAccount(address(chog), 2)); // Chog stays in the wallet
        uint256 id = _mint(alice, L_2K);
        vm.startPrank(alice);
        pm.approve(address(vv), id);
        vm.expectRevert(AccountVault.AssetsNotAccepted.selector);
        vv.depositPosition(id);
        vm.stopPrank();
    }

    function test_deposit_atMostTwoPositions() external {
        _openAccount(alice, 1);
        AccountVault vv = AccountVault(registry.vaultOf(address(chog), 1));
        _depositPos(alice, 1, _mint(alice, L_2K));
        _depositPos(alice, 1, _mint(alice, L_2K));
        uint256 third = _mint(alice, L_2K);
        vm.startPrank(alice);
        pm.approve(address(vv), third);
        vm.expectRevert(AccountVault.TooManyPositions.selector);
        vv.depositPosition(third);
        vm.stopPrank();
    }

    function test_safeTransferIsRefused() external {
        _alice1(L_2K);
        vm.expectRevert(AccountVault.SafeTransferRejected.selector);
        v.onERC721Received(address(0), address(0), 1, "");
    }

    function test_withdraw_debtFree_needsNoPrice_andReleasesTheChog() external {
        _alice1(L_2K);
        oracle.setDown(true);
        vm.prank(alice);
        v.withdrawPosition(pos, alice);
        assertEq(pm.ownerOf(pos), alice);
        assertEq(v.positionCount(), 0);
        assertTrue(v.isEmpty());
        vm.prank(alice);
        escrow.release(address(chog), 1, alice);
        assertEq(chog.ownerOf(1), alice);
    }

    function test_withdraw_onlyController_andOnlyHeld() external {
        _alice1(L_2K);
        vm.prank(bob);
        vm.expectRevert(AccountVault.NotController.selector);
        v.withdrawPosition(pos, bob);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.PositionNotHeld.selector, 12345));
        v.withdrawPosition(12345, alice);
        vm.prank(alice);
        vm.expectRevert(AccountVault.ZeroAddress.selector);
        v.withdrawPosition(pos, address(0));
    }

    function test_collectFees_controllerOnly_andNotCounted() external {
        _alice1(L_2K);
        pm.addFees(pos, 5e6, 7e6);
        // the credit pool's valuation ignores fees
        (, uint256 before_) = pool.positionValue(pos);
        pm.addFees(pos, 1e6, 1e6);
        (, uint256 after_) = pool.positionValue(pos);
        assertEq(before_, after_);
        vm.prank(bob);
        vm.expectRevert(AccountVault.NotController.selector);
        v.collectFees(pos, bob);
        uint256 balBefore0 = usdc.balanceOf(alice) + wmon.balanceOf(alice);
        vm.prank(alice);
        v.collectFees(pos, alice);
        assertGt(usdc.balanceOf(alice) + wmon.balanceOf(alice), balBefore0);
    }

    function test_unwind_onlyTheCreditModule() external {
        _alice1(L_2K);
        vm.prank(alice);
        vm.expectRevert(AccountVault.OnlyCreditModule.selector);
        v.unwindPosition(pos);
    }

    // ---------------------------------------------------------------- valuation

    function test_valuation_countsTheOraclePrice_atTheConfiguredLtv() external {
        _alice1(L_2K);
        (bool ok, uint256 value) = pool.positionValue(pos);
        assertTrue(ok);
        assertApproxEqRel(value, 2_000 * USDC, 0.001e18, "about $2,000");
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertTrue(d.priceOk);
        assertEq(d.collateralValue, value);
        assertEq(d.borrowPower, value * 3_500 / 10_000, "LTV 35%");
        assertEq(d.liquidationValue, value * 5_250 / 10_000, "threshold 52.5%");
    }

    function test_borrowAgainstAPosition_atExactLimit() external {
        _alice1(L_2K);
        uint256 power = pool.accountData(k).borrowPower;
        vm.prank(alice);
        vm.expectPartialRevert(ChogCreditPool.BorrowLimitExceeded.selector);
        pool.borrow(k, power + 1);
        vm.prank(alice);
        pool.borrow(k, power);
        assertEq(pool.debtOf(k), power);
        assertEq(usdc.balanceOf(alice), power);
    }

    function test_valuation_isCappedPerAccount() external {
        _alice1(L_2K * 100); // about $200,000 raw
        (, uint256 raw) = pool.positionValue(pos);
        assertGt(raw, 190_000 * USDC);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertEq(d.collateralValue, 50_000 * USDC, "counted value is capped");
        assertEq(d.borrowPower, 17_500 * USDC);
    }

    function test_valuation_addsToTokenCollateral() external {
        _alice1(L_2K);
        _deposit(alice, 1, address(wmon), 1_000 * WMON); // $2,000 at LTV 50%
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        (, uint256 raw) = pool.positionValue(pos);
        assertEq(d.collateralValue, raw + 2_000 * USDC);
        assertEq(d.borrowPower, raw * 3_500 / 10_000 + 1_000 * USDC);
    }

    function test_outOfRange_isValuedAsASingleToken() external {
        _openAccount(alice, 1);
        uint160 sqrtP = _oracleSqrt();
        int24 t = _tickAtOrBelow(sqrtP);
        // entirely below the current price, then entirely above it
        uint256 below = pm.mint(alice, address(lpPool), t - 1_200, t - 600, L_2K);
        uint256 above = pm.mint(alice, address(lpPool), t + 600, t + 1_200, L_2K);
        (bool ok1, uint256 vBelow) = _valueOf(below);
        (bool ok2, uint256 vAbove) = _valueOf(above);
        assertTrue(ok1 && ok2);
        // recompute independently from the library
        (uint256 a0, uint256 a1) =
            LpMath.amountsForLiquidity(sqrtP, LpMath.sqrtRatioAtTick(t - 1_200), LpMath.sqrtRatioAtTick(t - 600), L_2K);
        assertTrue(a0 == 0 || a1 == 0, "below the range holds a single token");
        address single = a0 != 0 ? lpPool.token0() : lpPool.token1();
        assertEq(vBelow, oracle.quote(single, a0 + a1));
        (a0, a1) =
            LpMath.amountsForLiquidity(sqrtP, LpMath.sqrtRatioAtTick(t + 600), LpMath.sqrtRatioAtTick(t + 1_200), L_2K);
        assertTrue(a0 == 0 || a1 == 0);
        single = a0 != 0 ? lpPool.token0() : lpPool.token1();
        assertEq(vAbove, oracle.quote(single, a0 + a1));
        assertGt(vBelow, 0);
        assertGt(vAbove, 0);
    }

    function _valueOf(uint256 id) internal returns (bool, uint256) {
        _depositPos(alice, 1, id);
        return pool.positionValue(id);
    }

    function test_malformedPositionReply_isUnpriceable() external {
        _alice1(L_2K);
        pm.setShortReply(true);
        (bool ok,) = pool.positionValue(pos);
        assertFalse(ok);
        assertFalse(pool.positionAccepted(pos));
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1);
    }

    function test_withdraw_bumpsTheStateNonce() external {
        _alice1(L_2K);
        uint256 n0 = v.stateNonce();
        vm.prank(alice);
        v.withdrawPosition(pos, alice);
        assertEq(v.stateNonce(), n0 + 1);
    }

    function test_deposit_failsIfTheVaultDidNotEndUpOwningIt() external {
        _openAccount(alice, 1);
        AccountVault vv = AccountVault(registry.vaultOf(address(chog), 1));
        uint256 id = _mint(alice, L_2K);
        pm.setTransferIsNoop(true);
        vm.startPrank(alice);
        pm.approve(address(vv), id);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.PositionNotReceived.selector, id));
        vv.depositPosition(id);
        vm.stopPrank();
        assertEq(vv.positionCount(), 0);
    }

    function test_zeroLiquidityPosition_isWorthNothing_andNeedsNoPrice() external {
        _alice1(L_2K);
        pm.setLiquidityForTest(pos, 0);
        oracle.setDown(true);
        (bool ok, uint256 value) = pool.positionValue(pos);
        assertTrue(ok);
        assertEq(value, 0);
    }

    // ---------------------------------------------------------------- fail closed

    function test_poolPriceFarFromOracle_makesThePositionUnpriceable() external {
        _alice1(L_2K);
        _supply(lender, 1);
        uint160 s = lpPool.sqrtPriceX96();
        lpPool.setSqrtPrice(uint160(uint256(s) * 10_247 / 10_000)); // ~5% price gap
        (bool ok,) = pool.positionValue(pos);
        assertFalse(ok);
        assertFalse(pool.accountData(k).priceOk);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1);
        // within the 2% bound still prices
        lpPool.setSqrtPrice(uint160(uint256(s) * 10_090 / 10_000)); // ~1.8% price gap
        (ok,) = pool.positionValue(pos);
        assertTrue(ok);
        lpPool.setSqrtPrice(uint160(uint256(s) * 10_110 / 10_000)); // ~2.2% price gap
        (ok,) = pool.positionValue(pos);
        assertFalse(ok);
    }

    function test_unpriceable_blocksBorrowWithdrawAndLiquidate_butNotRepay() external {
        _alice1(L_2K);
        _borrow(alice, 1, 300 * USDC);
        lpPool.setReverts(true); // the pool itself cannot be read
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1);
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawPosition(pos, alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.liquidate(k, 1);
        // repayment and lender exits never need a price
        deal(address(usdc), alice, 300 * USDC);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, 300 * USDC);
        v.withdrawPosition(pos, alice); // debt-free: allowed with no price
        vm.stopPrank();
        assertEq(pm.ownerOf(pos), alice);
    }

    function test_oracleOutage_failsClosed() external {
        _alice1(L_2K);
        oracle.setDown(true);
        (bool ok,) = pool.positionValue(pos);
        assertFalse(ok);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1);
    }

    function test_burnedPosition_isUnpriceable() external {
        _alice1(L_2K);
        pm.burnForTest(pos);
        (bool ok,) = pool.positionValue(pos);
        assertFalse(ok);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.borrow(k, 1);
    }

    // ---------------------------------------------------------------- withdrawal while indebted

    function test_withdrawPosition_whileIndebted_followsTheBorrowLimit() external {
        _alice1(L_2K);
        _deposit(alice, 1, address(wmon), 1_000 * WMON); // power 1000 from tokens + ~700 from the position
        _borrow(alice, 1, 900 * USDC);
        vm.prank(alice);
        v.withdrawPosition(pos, alice); // tokens alone (1000) still cover 900
        assertEq(pm.ownerOf(pos), alice);
        // put it back and borrow more than the tokens alone allow
        _depositPos(alice, 1, pos);
        _borrow(alice, 1, 500 * USDC); // total 1400, tokens cover 1000, the position is needed
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawPosition(pos, alice);
        assertEq(pm.ownerOf(pos), address(v));
    }

    function test_tokenWithdrawal_isNowCheckedAgainstThePositionToo() external {
        _alice1(L_2K);
        _deposit(alice, 1, address(wmon), 1_000 * WMON);
        _borrow(alice, 1, 1_500 * USDC); // needs both
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawERC20(address(wmon), 500 * WMON, alice);
    }

    // ---------------------------------------------------------------- liquidation

    function test_liquidation_unwindsFirst_andProceedsRepayTheDebt() external {
        _alice1(L_2K);
        uint256 power = pool.accountData(k).borrowPower;
        _borrow(alice, 1, power - 10 * USDC);
        // WMON falls from 2 to 0.5 USDC: a full-range position is worth sqrt(0.25) = half as much
        _setWmonPrice(5e5);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertTrue(d.priceOk);
        assertLt(d.liquidationValue, d.debt, "liquidatable");

        uint256 cashBefore = pool.availableLiquidity();
        uint256 liqBefore = usdc.balanceOf(liquidator);
        vm.prank(liquidator);
        uint256 repaid = pool.liquidate(k, type(uint128).max);

        assertEq(repaid, 0, "the unwind alone restored health, so the liquidator paid nothing");
        assertEq(usdc.balanceOf(liquidator), liqBefore);
        assertEq(v.accounted(address(usdc)), 0, "the loan-token half went to the debt");
        assertGt(v.accounted(address(wmon)), 0, "the WMON half is now plain collateral");
        assertGt(pool.availableLiquidity(), cashBefore, "proceeds reached the pool");
        assertLt(pool.debtOf(k), d.debt);
        // the position NFT is still there but empty
        (bool ok, uint256 value) = pool.positionValue(pos);
        assertTrue(ok);
        assertEq(value, 0);
        assertEq(pm.ownerOf(pos), address(v));
    }

    function test_liquidation_afterUnwind_stillLiquidatableTokensAreSeized() external {
        _alice1(L_2K);
        uint256 power = pool.accountData(k).borrowPower;
        _borrow(alice, 1, power);
        _setWmonPrice(2e5); // WMON falls to 0.20 USDC: far below
        assertLt(pool.accountData(k).liquidationValue, pool.debtOf(k));

        uint256 wmonBefore = wmon.balanceOf(liquidator);
        uint256 repaid = _liquidate(liquidator, 1, 1_000 * USDC);
        assertGt(repaid, 0);
        assertGt(wmon.balanceOf(liquidator), wmonBefore, "the liquidator received seized WMON");
        assertEq(v.accounted(address(usdc)), 0);
    }

    function test_liquidation_ofAHealthyAccountWithAPositionStillReverts() external {
        _alice1(L_2K);
        _borrow(alice, 1, 100 * USDC);
        vm.prank(liquidator);
        vm.expectPartialRevert(ChogCreditPool.NotLiquidatable.selector);
        pool.liquidate(k, 1);
        assertEq(v.holdsPosition(pos) ? v.positionCount() : 0, 1);
    }

    function test_liquidation_unwindIsBlockedByAPriceGap() external {
        _alice1(L_2K);
        uint256 power = pool.accountData(k).borrowPower;
        _borrow(alice, 1, power);
        oracle.setPrice(address(wmon), 1 * USDC); // oracle moves, the pool does not
        vm.prank(liquidator);
        vm.expectRevert(ChogCreditPool.OracleFailure.selector);
        pool.liquidate(k, 1);
        assertEq(pm.ownerOf(pos), address(v), "nothing was unwound at a manipulated price");
    }

    // ---------------------------------------------------------------- constructor rules

    function test_constructor_lpValidation() external {
        address r = address(registry);
        ChogCreditPool.PoolConfig memory c = _poolConfig();
        ChogCreditPool.CollateralConfig[] memory cols = _collaterals(false);

        ChogCreditPool.LpConfig memory lp = _validLp();
        new ChogCreditPool(r, c, cols, lp); // control

        lp = _validLp();
        lp.pools = new ChogCreditPool.LpPoolConfig[](0);
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.positionManager = address(0); // pools but no manager
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.pools[0].ltvBps = 5_250; // ltv == threshold
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.pools[0].maxDeviationBps = 0;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.pools[0].maxDeviationBps = 1_001;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.pools[0].maxCountedValue = 0;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        lp = _validLp();
        lp.pools[0].liquidationThresholdBps = 9_600; // threshold * (1 + bonus) > 100%
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        // bonus above the 20% ceiling while the solvency rule is still satisfied
        lp = _validLp();
        lp.pools[0].liquidationBonusBps = 2_001;
        lp.pools[0].liquidationThresholdBps = 4_000;
        lp.pools[0].ltvBps = 3_000;
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        // a position manager that has no factory
        lp = _validLp();
        lp.positionManager = address(new MockPositionManager(address(0)));
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        // the loan token as a collateral (it is vault-allowed here because LP positions pay out in it)
        ChogCreditPool.CollateralConfig[] memory loanAsCol = new ChogCreditPool.CollateralConfig[](2);
        loanAsCol[0] = ChogCreditPool.CollateralConfig(address(wmon), 5_000, 7_500, 500, type(uint256).max);
        loanAsCol[1] = ChogCreditPool.CollateralConfig(address(usdc), 5_000, 7_500, 500, type(uint256).max);
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, loanAsCol, _validLp());

        // a pool the factory did not create
        lp = _validLp();
        lp.pools[0].pool = address(new MockV3Pool(address(wmon), address(usdc), 3000));
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        // a pool holding a token the pool does not know as loan token or collateral
        lp = _validLp();
        lp.pools[0].pool = v3f.createPool(address(wmon), address(btc), 500);
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);

        // duplicates
        lp = _validLp();
        lp.pools = new ChogCreditPool.LpPoolConfig[](2);
        lp.pools[0] = _validLp().pools[0];
        lp.pools[1] = _validLp().pools[0];
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        this.mkPool(r, c, cols, lp);
    }

    function _validLp() internal view returns (ChogCreditPool.LpConfig memory lp) {
        lp.positionManager = address(pm);
        lp.pools = new ChogCreditPool.LpPoolConfig[](1);
        lp.pools[0] = ChogCreditPool.LpPoolConfig(address(lpPool), 3_500, 5_250, 500, 200, 50_000 * USDC);
    }

    // ---------------------------------------------------------------- package sale carries the position

    function test_debtFreeSale_carriesThePosition() external {
        _alice1(L_2K);
        AccountTransferCoordinator coord = AccountTransferCoordinator(escrow.coordinator());
        (address buyer, uint256 buyerPk) = makeAddrAndKey("lpBuyer");
        AccountTransferCoordinator.Acceptance memory a = AccountTransferCoordinator.Acceptance({
            key: k,
            seller: alice,
            buyer: buyer,
            paymentToken: address(usdc),
            price: 0,
            stateNonce: v.stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1
        });
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashAcceptance(a));
        vm.prank(alice);
        coord.executeSale(a, abi.encodePacked(r, s, vv));
        assertEq(pm.ownerOf(pos), address(v), "the position never leaves the vault");
        vm.prank(buyer);
        v.withdrawPosition(pos, buyer);
        assertEq(pm.ownerOf(pos), buyer);
    }

    function test_depositAfterSigning_voidsAnAcceptance() external {
        _alice1(L_2K);
        AccountTransferCoordinator coord = AccountTransferCoordinator(escrow.coordinator());
        (address buyer, uint256 buyerPk) = makeAddrAndKey("lpBuyer2");
        AccountTransferCoordinator.Acceptance memory a = AccountTransferCoordinator.Acceptance({
            key: k,
            seller: alice,
            buyer: buyer,
            paymentToken: address(usdc),
            price: 0,
            stateNonce: v.stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1
        });
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashAcceptance(a));
        bytes memory sig = abi.encodePacked(r, s, vv);
        _depositPos(alice, 1, _mint(alice, L_2K)); // a second position appears after signing
        vm.prank(alice);
        vm.expectPartialRevert(AccountTransferCoordinator.StateChanged.selector);
        coord.executeSale(a, sig);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_countedValueNeverExceedsRawOrCap(uint128 liquidity, uint256 gapBps) external {
        liquidity = uint128(bound(liquidity, 1, 1e18));
        gapBps = bound(gapBps, 0, 150); // within the 2% price-gap bound
        _alice1(liquidity);
        uint160 s = lpPool.sqrtPriceX96();
        lpPool.setSqrtPrice(uint160(uint256(s) * (10_000 + gapBps / 2) / 10_000));
        (bool ok, uint256 raw) = pool.positionValue(pos);
        assertTrue(ok);
        ChogCreditPool.AccountData memory d = pool.accountData(k);
        assertLe(d.collateralValue, raw);
        assertLe(d.collateralValue, 50_000 * USDC);
        assertEq(d.collateralValue, raw < 50_000 * USDC ? raw : 50_000 * USDC);
        assertLe(d.borrowPower, d.collateralValue * 3_500 / 10_000);
    }
}

/// @dev Without an LP configuration the vault refuses positions and the pool ignores them.
contract LpDisabledTest is CreditBase {
    function test_positionsAreNotSupported() external {
        _supply(lender, 1_000 * USDC);
        vm.prank(alice);
        AccountVault vv = AccountVault(registry.createAccount(address(chog), 1));
        vm.prank(alice);
        chog.safeTransferFrom(alice, address(escrow), 1);
        assertEq(pool.positionManager(), address(0));
        assertFalse(pool.positionAccepted(1));
        assertEq(registry.positionManager(), address(0));
        vm.prank(alice);
        vm.expectRevert(AccountVault.PositionsNotSupported.selector);
        vv.depositPosition(1);
    }
}
