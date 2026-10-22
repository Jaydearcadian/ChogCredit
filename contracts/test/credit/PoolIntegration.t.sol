// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";

/// @dev The credit pool working together with escrow, the vault and the package-sale coordinator.
contract PoolIntegrationTest is CreditBase {
    AccountTransferCoordinator internal coord;
    address internal buyer;
    uint256 internal buyerPk;

    function setUp() public override {
        super.setUp();
        coord = AccountTransferCoordinator(escrow.coordinator());
        (buyer, buyerPk) = makeAddrAndKey("buyer");
    }

    function _acceptance(uint256 id, address seller, uint256 price)
        internal
        view
        returns (AccountTransferCoordinator.Acceptance memory a, bytes memory sig)
    {
        bytes32 k = _key(id);
        a = AccountTransferCoordinator.Acceptance({
            key: k,
            seller: seller,
            buyer: buyer,
            paymentToken: address(usdc),
            price: price,
            stateNonce: AccountVault(registry.vaultOf(address(chog), id)).stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashAcceptance(a));
        sig = abi.encodePacked(r, s, v);
    }

    function test_fundedAccountWithDebtCannotBeSold_untilRepaid() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        _borrow(alice, 1, 400 * USDC);
        (AccountTransferCoordinator.Acceptance memory a, bytes memory sig) = _acceptance(1, alice, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.HasLiabilities.selector, ReleaseBlocker.HasDebt)
        );
        coord.executeSale(a, sig);

        deal(address(usdc), alice, 400 * USDC);
        bytes32 k = _key(1);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, 400 * USDC);
        coord.executeSale(a, sig); // same acceptance still valid: repaying did not touch the vault
        vm.stopPrank();
        assertEq(escrow.beneficialOwnerOf(k), buyer);
    }

    function test_afterSale_newOwnerBorrows_oldOwnerCannot() external {
        _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        (AccountTransferCoordinator.Acceptance memory a, bytes memory sig) = _acceptance(1, alice, 0);
        vm.prank(alice);
        coord.executeSale(a, sig);

        bytes32 k = _key(1);
        vm.prank(alice);
        vm.expectRevert(ChogCreditPool.NotController.selector);
        pool.borrow(k, 1 * USDC);

        vm.prank(buyer);
        pool.borrow(k, 300 * USDC);
        assertEq(usdc.balanceOf(buyer), 300 * USDC, "proceeds go to the NEW owner's wallet");
        assertEq(pool.debtOf(k), 300 * USDC);
        assertEq(v.accounted(address(wmon)), 1_000 * WMON, "the collateral moved with the Chog");
    }

    function test_liquidationMakesAPendingSaleFail_noSurpriseForTheBuyer() external {
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 1_000 * WMON);
        // an acceptance is signed while the account is healthy and debt-free
        (AccountTransferCoordinator.Acceptance memory a, bytes memory sig) = _acceptance(1, alice, 0);
        _borrow(alice, 1, 1_000 * USDC);
        oracle.setPrice(address(wmon), 1_200_000);
        _liquidate(liquidator, 1, 1_000 * USDC);
        // collateral changed and debt exists: either condition alone voids the sale
        vm.prank(alice);
        vm.expectRevert();
        coord.executeSale(a, sig);
    }

    function test_fullLifecycle() external {
        // lender funds, borrower escrows and deposits, borrows, time passes, repays with interest, exits, lender profits
        uint256 shares = _supply(lender, 10_000 * USDC);
        AccountVault v = _fund(alice, 1, 1_000 * WMON);
        bytes32 k = _key(1);
        _borrow(alice, 1, 800 * USDC);
        vm.warp(block.timestamp + 180 days);

        uint256 debt = pool.debtOf(k);
        assertGt(debt, 800 * USDC);
        deal(address(usdc), alice, debt);
        vm.startPrank(alice);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(k, debt);
        v.withdrawERC20(address(wmon), 1_000 * WMON, alice);
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), alice);
        assertEq(pool.totalScaledDebt(), 0);

        vm.prank(lender);
        uint256 out = pool.redeem(shares);
        assertGt(out, 10_000 * USDC, "the lender earned the interest");
        assertApproxEqAbs(out, 10_000 * USDC + (debt - 800 * USDC), 2);
    }
}
