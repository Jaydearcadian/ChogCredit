// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";

/// @dev Debt-bearing package sales (docs/DEBT_BEARING_SALES_SPEC.md). Setup: alice holds Chog 1 with 1,000 WMON
///      (2 USDC each, so value 2,000 USDC, borrowing power 1,000, liquidation value 1,500) and 600 USDC of debt.
contract DebtSaleTest is CreditBase {
    AccountTransferCoordinator internal coord;
    address internal buyer;
    uint256 internal buyerPk;
    bytes32 internal k;

    function setUp() public override {
        super.setUp();
        coord = AccountTransferCoordinator(escrow.coordinator());
        (buyer, buyerPk) = makeAddrAndKey("buyer");
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 600 * USDC);
        k = _key(1);
        deal(address(usdc), buyer, 5_000 * USDC);
        vm.prank(buyer);
        usdc.approve(address(coord), type(uint256).max);
    }

    function _terms(uint256 price, uint256 debtRepay)
        internal
        view
        returns (AccountTransferCoordinator.DebtAcceptance memory a)
    {
        a = AccountTransferCoordinator.DebtAcceptance({
            key: k,
            seller: alice,
            buyer: buyer,
            paymentToken: address(usdc),
            price: price,
            stateNonce: AccountVault(registry.vaultOf(address(chog), 1)).stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1,
            pool: address(pool),
            maxDebt: 700 * USDC,
            minCollateralValue: 2_000 * USDC,
            minHealthBps: 20_000,
            debtRepay: debtRepay
        });
    }

    function _sign(AccountTransferCoordinator.DebtAcceptance memory a) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashDebtAcceptance(a));
        return abi.encodePacked(r, s, v);
    }

    function _sell(AccountTransferCoordinator.DebtAcceptance memory a) internal {
        bytes memory sig = _sign(a);
        vm.prank(alice);
        coord.executeDebtSale(a, sig);
    }

    function _expectSaleReverts(AccountTransferCoordinator.DebtAcceptance memory a, bytes memory err) internal {
        bytes memory sig = _sign(a);
        vm.prank(alice);
        vm.expectRevert(err);
        coord.executeDebtSale(a, sig);
    }

    // ---------------------------------------------------------------- success paths

    function test_debtTravelsWithTheAccount_noPayoff() external {
        uint256 sellerBefore = usdc.balanceOf(alice);
        _sell(_terms(500 * USDC, 0));

        assertEq(escrow.beneficialOwnerOf(k), buyer);
        assertEq(pool.debtOf(k), 600 * USDC, "debt is untouched");
        assertEq(usdc.balanceOf(alice) - sellerBefore, 500 * USDC, "seller receives the full price");
        assertEq(usdc.balanceOf(buyer), 4_500 * USDC);
        assertTrue(registry.isController(k, buyer));
        assertFalse(registry.isController(k, alice));
        // The buyer now owns the position and can act on it: borrow within power, and the old owner cannot.
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.NotController.selector);
        pool.borrow(k, 1);
        vm.prank(buyer);
        pool.borrow(k, 100 * USDC);
        assertEq(pool.debtOf(k), 700 * USDC);
    }

    function test_payoff_reducesDebtAndSplitsThePayment() external {
        uint256 sellerBefore = usdc.balanceOf(alice);
        uint256 cashBefore = pool.availableLiquidity();
        _sell(_terms(500 * USDC, 300 * USDC));

        assertEq(pool.debtOf(k), 300 * USDC, "300 of the price repaid the loan");
        assertEq(pool.availableLiquidity(), cashBefore + 300 * USDC);
        assertEq(usdc.balanceOf(alice) - sellerBefore, 200 * USDC, "seller gets price minus payoff");
        assertEq(usdc.balanceOf(buyer), 4_500 * USDC, "buyer paid exactly the price");
        assertEq(usdc.balanceOf(address(coord)), 0, "coordinator never keeps funds");
        assertEq(usdc.allowance(address(coord), address(pool)), 0, "no lingering approval");
        assertEq(escrow.beneficialOwnerOf(k), buyer);
    }

    function test_fullPayoff_leavesADebtFreeAccount() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(700 * USDC, 600 * USDC);
        a.maxDebt = 0;
        _sell(a);
        assertEq(pool.debtOf(k), 0);
        assertEq(registry.debtOf(k), 0);
        assertEq(usdc.balanceOf(address(coord)), 0);
        assertEq(escrow.beneficialOwnerOf(k), buyer);
    }

    function test_payoff_priceEqualsRepay_sellerGetsNothing() external {
        uint256 sellerBefore = usdc.balanceOf(alice);
        _sell(_terms(200 * USDC, 200 * USDC));
        assertEq(usdc.balanceOf(alice), sellerBefore);
        assertEq(pool.debtOf(k), 400 * USDC);
    }

    // ---------------------------------------------------------------- consent and state

    function test_wrongSignerReverts() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        (, uint256 otherPk) = makeAddrAndKey("other");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, coord.hashDebtAcceptance(a));
        vm.prank(alice);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeDebtSale(a, abi.encodePacked(r, s, v));
    }

    function test_everySignedFieldIsBound() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(100 * USDC, 0);
        bytes memory sig = _sign(a);
        AccountTransferCoordinator.DebtAcceptance memory c = _clone(a);
        c.price += 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.maxDebt += 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.minCollateralValue -= 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.minHealthBps -= 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.debtRepay += 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.salt += 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.deadline += 1;
        _expectBadSig(c, sig);
        c = _clone(a);
        c.pool = address(0xBEEF);
        _expectBadSig(c, sig);
        c = _clone(a);
        c.paymentToken = address(wmon);
        _expectBadSig(c, sig);
    }

    function _expectBadSig(AccountTransferCoordinator.DebtAcceptance memory c, bytes memory sig) internal {
        vm.prank(alice);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeDebtSale(c, sig);
    }

    function _clone(AccountTransferCoordinator.DebtAcceptance memory a)
        internal
        pure
        returns (AccountTransferCoordinator.DebtAcceptance memory c)
    {
        c = AccountTransferCoordinator.DebtAcceptance(
            a.key,
            a.seller,
            a.buyer,
            a.paymentToken,
            a.price,
            a.stateNonce,
            a.epoch,
            a.deadline,
            a.salt,
            a.pool,
            a.maxDebt,
            a.minCollateralValue,
            a.minHealthBps,
            a.debtRepay
        );
    }

    function test_onlySellerCanExecute_andNotAfterDeadline_orTwice() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        vm.prank(bob);
        vm.expectRevert(AccountTransferCoordinator.NotSeller.selector);
        coord.executeDebtSale(a, sig);

        vm.warp(a.deadline + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.Expired.selector, a.deadline));
        coord.executeDebtSale(a, sig);
        vm.warp(a.deadline - 1);

        vm.prank(alice);
        coord.executeDebtSale(a, sig);
        // sold; the new owner (buyer) can't be sold again with the same signature, and alice is no longer owner
        vm.prank(alice);
        vm.expectRevert(AccountTransferCoordinator.SellerNotBeneficialOwner.selector);
        coord.executeDebtSale(a, sig);
    }

    function test_ownershipChangeAndChangeBack_voidsAnOlderAcceptance() external {
        (address s, uint256 sPk) = makeAddrAndKey("keySeller");
        chog.mint(s, 9);
        _fund(s, 9, 1_000 * WMON);
        _borrow(s, 9, 100 * USDC);
        bytes32 k9 = _key(9);
        vm.prank(buyer);
        usdc.approve(address(coord), type(uint256).max);

        AccountTransferCoordinator.DebtAcceptance memory older = _termsFor(k9, s, buyer, 1);
        bytes memory olderSig = _sign(older);

        // s sells to buyer on a different acceptance, then buyer sells it straight back to s
        AccountTransferCoordinator.DebtAcceptance memory first = _termsFor(k9, s, buyer, 2);
        bytes memory firstSig = _sign(first);
        vm.prank(s);
        coord.executeDebtSale(first, firstSig);
        AccountTransferCoordinator.DebtAcceptance memory back = _termsFor(k9, buyer, s, 3);
        (uint8 v, bytes32 r, bytes32 sg) = vm.sign(sPk, coord.hashDebtAcceptance(back));
        vm.prank(buyer);
        coord.executeDebtSale(back, abi.encodePacked(r, sg, v));
        assertEq(escrow.beneficialOwnerOf(k9), s);

        // s is the beneficial owner again, the vault is unchanged, but the epoch moved twice
        vm.prank(s);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.EpochChanged.selector, older.epoch, older.epoch + 2)
        );
        coord.executeDebtSale(older, olderSig);
    }

    function _termsFor(bytes32 key, address seller, address buyer_, uint256 salt)
        internal
        view
        returns (AccountTransferCoordinator.DebtAcceptance memory a)
    {
        a = _terms(0, 0);
        a.key = key;
        a.seller = seller;
        a.buyer = buyer_;
        a.salt = salt;
        a.stateNonce = AccountVault(registry.accountInfo(key).vault).stateNonce();
        a.epoch = escrow.epochOf(key);
        a.maxDebt = 1_000 * USDC;
    }

    function test_buyerCanCancel() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        bytes32 digest = coord.hashDebtAcceptance(a);
        vm.prank(alice);
        vm.expectRevert(AccountTransferCoordinator.NotBuyer.selector);
        coord.cancelDebt(a);
        vm.prank(buyer);
        coord.cancelDebt(a);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.AlreadyUsed.selector, digest));
        coord.executeDebtSale(a, sig);
    }

    function test_vaultChangeAfterSigning_voidsTheAcceptance() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        uint256 signedNonce = a.stateNonce;
        _deposit(alice, 1, address(wmon), 1 * WMON);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.StateChanged.selector, signedNonce, signedNonce + 1)
        );
        coord.executeDebtSale(a, sig);
    }

    function test_liquidationAfterSigning_voidsTheAcceptance() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        oracle.setPrice(address(wmon), 1 * USDC); // value 1000, liquidation value 750 < 600? no: 750 > 600, healthy
        oracle.setPrice(address(wmon), 7e5); // liquidation value 525 < 600: liquidatable
        _liquidate(liquidator, 1, 100 * USDC);
        vm.prank(alice);
        vm.expectRevert(); // the seizure bumped the vault nonce (or the account is now unhealthy)
        coord.executeDebtSale(a, sig);
    }

    // ---------------------------------------------------------------- bounds

    function test_borrowAfterSigning_isStoppedByTheDebtCeiling() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(100 * USDC, 0);
        bytes memory sig = _sign(a);
        _borrow(alice, 1, 150 * USDC); // 750 debt > 700 ceiling; a borrow does not bump the vault nonce
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.DebtAboveCeiling.selector, 750 * USDC, 700 * USDC)
        );
        coord.executeDebtSale(a, sig);
        assertEq(escrow.beneficialOwnerOf(k), alice, "nothing changed");
        assertEq(usdc.balanceOf(buyer), 5_000 * USDC, "buyer paid nothing");
    }

    function test_interestAccrual_isCoveredByTheCeiling() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        a.maxDebt = 600 * USDC; // exactly the current debt: any accrued interest breaks it
        a.deadline = block.timestamp + 60 days;
        bytes memory sig = _sign(a);
        vm.warp(block.timestamp + 30 days);
        uint256 debt = pool.debtOf(k);
        assertGt(debt, 600 * USDC);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.DebtAboveCeiling.selector, debt, 600 * USDC));
        coord.executeDebtSale(a, sig);
    }

    function test_priceFall_breaksCollateralFloor() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        oracle.setPrice(address(wmon), 18e5); // 1.8 USDC: value 1800 < 2000 floor, still healthy
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.CollateralBelowFloor.selector, 1_800 * USDC, 2_000 * USDC)
        );
        coord.executeDebtSale(a, sig);
    }

    function test_priceFall_breaksHealthFloor() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        a.minCollateralValue = 0;
        bytes memory sig = _sign(a);
        oracle.setPrice(address(wmon), 15e5); // liquidation value 1125 / 600 = 18750 bps < 20000
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.HealthBelowFloor.selector, 18_750, 20_000));
        coord.executeDebtSale(a, sig);
    }

    function test_alreadyLiquidatable_cannotBeSold_evenWithZeroFloors() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        a.maxDebt = type(uint256).max;
        a.minCollateralValue = 0;
        a.minHealthBps = 0;
        bytes memory sig = _sign(a);
        oracle.setPrice(address(wmon), 7e5); // liquidation value 525 < debt 600
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.AlreadyLiquidatable.selector, 8_750));
        coord.executeDebtSale(a, sig);
    }

    function test_oracleOutage_failsClosed() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes memory sig = _sign(a);
        oracle.setDown(true);
        vm.prank(alice);
        vm.expectRevert(AccountTransferCoordinator.PriceUnavailable.selector);
        coord.executeDebtSale(a, sig);
    }

    function test_wrongPoolReverts_beforeAnyPoolCall() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        a.pool = address(0xFA4E);
        _expectSaleReverts(
            a, abi.encodeWithSelector(AccountTransferCoordinator.WrongPool.selector, address(0xFA4E), address(pool))
        );
    }

    function test_debtFreeAccount_mustUseTheDebtFreePath() external {
        deal(address(usdc), alice, 600 * USDC);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, 600 * USDC);
        vm.stopPrank();
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        _expectSaleReverts(a, abi.encodeWithSelector(AccountTransferCoordinator.NoDebtToSell.selector));
    }

    // ---------------------------------------------------------------- payoff rules

    function test_payoff_requiresLoanToken() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(10 ether, 1 * USDC);
        a.paymentToken = address(wmon);
        deal(address(wmon), buyer, 100 ether);
        vm.prank(buyer);
        wmon.approve(address(coord), type(uint256).max);
        _expectSaleReverts(
            a,
            abi.encodeWithSelector(
                AccountTransferCoordinator.RepayNeedsLoanToken.selector, address(wmon), address(usdc)
            )
        );
    }

    function test_payoff_cannotExceedPriceOrDebt() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(100 * USDC, 101 * USDC);
        _expectSaleReverts(
            a, abi.encodeWithSelector(AccountTransferCoordinator.RepayExceedsPrice.selector, 101 * USDC, 100 * USDC)
        );
        a = _terms(900 * USDC, 601 * USDC);
        _expectSaleReverts(
            a, abi.encodeWithSelector(AccountTransferCoordinator.RepayExceedsDebt.selector, 601 * USDC, 600 * USDC)
        );
    }

    function test_buyerWithoutFunds_revertsAtomically() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(500 * USDC, 300 * USDC);
        bytes memory sig = _sign(a);
        vm.prank(buyer);
        usdc.approve(address(coord), 100 * USDC); // not enough
        vm.prank(alice);
        vm.expectRevert();
        coord.executeDebtSale(a, sig);
        assertEq(escrow.beneficialOwnerOf(k), alice);
        assertEq(pool.debtOf(k), 600 * USDC);
        assertEq(coord.used(coord.hashDebtAcceptance(a)), false, "no partial effects");
    }

    function test_existingDebtFreePath_stillRefusesDebt() external {
        AccountTransferCoordinator.Acceptance memory a = AccountTransferCoordinator.Acceptance({
            key: k,
            seller: alice,
            buyer: buyer,
            paymentToken: address(usdc),
            price: 0,
            stateNonce: AccountVault(registry.vaultOf(address(chog), 1)).stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashAcceptance(a));
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.HasLiabilities.selector, ReleaseBlocker.HasDebt)
        );
        coord.executeSale(a, abi.encodePacked(r, s, v));
    }

    // ---------------------------------------------------------------- fuzz: succeeds iff every bound holds

    function testFuzz_saleSucceedsExactlyWhenBoundsHold(
        uint256 maxDebt,
        uint256 minValue,
        uint256 minHealth,
        uint256 repay,
        uint256 priceWmon
    ) external {
        maxDebt = bound(maxDebt, 0, 1_000 * USDC);
        minValue = bound(minValue, 0, 4_000 * USDC);
        minHealth = bound(minHealth, 0, 60_000);
        repay = bound(repay, 0, 600 * USDC);
        priceWmon = bound(priceWmon, 6e5, 4 * USDC); // 0.6 to 4 USDC per WMON
        oracle.setPrice(address(wmon), priceWmon);

        AccountTransferCoordinator.DebtAcceptance memory a = _terms(700 * USDC, repay);
        a.maxDebt = maxDebt;
        a.minCollateralValue = minValue;
        a.minHealthBps = minHealth;
        bytes memory sig = _sign(a);

        uint256 debtAfter = 600 * USDC - repay;
        uint256 value = 1_000 * priceWmon; // 1000 WMON
        uint256 liq = value * 7_500 / 10_000;
        uint256 healthBefore = liq * 10_000 / (600 * USDC);
        uint256 healthAfter = debtAfter == 0 ? type(uint256).max : liq * 10_000 / debtAfter;
        bool ok = healthBefore >= 10_000 && debtAfter <= maxDebt && value >= minValue && healthAfter >= minHealth
            && healthAfter >= 10_000;

        vm.prank(alice);
        try coord.executeDebtSale(a, sig) {
            assertTrue(ok, "sale succeeded although a bound was violated");
            assertEq(escrow.beneficialOwnerOf(k), buyer);
            assertEq(pool.debtOf(k), debtAfter);
        } catch {
            assertFalse(ok, "sale reverted although every bound held");
            assertEq(escrow.beneficialOwnerOf(k), alice);
            assertEq(pool.debtOf(k), 600 * USDC);
        }
    }
}
