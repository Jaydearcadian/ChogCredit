// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

/// @dev $CHOG-style token: allowed in vaults so it travels with the Chog, but NOT collateral. It is worth zero
///      credit, it never blocks a withdrawal, and its liquidity is too thin to ever back a loan
///      (docs/evidence/LIQUIDITY_MODEL.md).
contract ChogTokenHeldTest is CreditBase {
    TestToken internal chogToken;
    bytes32 internal k;
    AccountVault internal v;

    function _extraTokens() internal override returns (address[] memory t) {
        chogToken = new TestToken("Mock CHOG", "mCHOG", 18);
        t = new address[](1);
        t[0] = address(chogToken);
    }

    function setUp() public override {
        super.setUp();
        _supply(lender, 10_000 * USDC);
        v = _fund(alice, 1, 1_000 * WMON); // 2,000 USDC of WMON: borrowing power 1,000
        k = _key(1);
    }

    function _holdChog(uint256 amount) internal {
        chogToken.mint(alice, amount);
        vm.startPrank(alice);
        chogToken.approve(address(v), amount);
        v.depositERC20(address(chogToken), amount);
        vm.stopPrank();
    }

    function test_heldToken_isVaultAllowed_butNotCollateral() external view {
        assertTrue(registry.isTokenAllowed(address(chogToken)));
        for (uint256 i; i < pool.collateralCount(); ++i) {
            assertTrue(pool.collateralAt(i).token != address(chogToken), "never a collateral");
        }
    }

    function test_holdingIt_addsNoBorrowingPower() external {
        ChogCreditPool.AccountData memory before_ = pool.accountData(k);
        _holdChog(5_000_000 * WMON); // a huge balance
        assertEq(v.accounted(address(chogToken)), 5_000_000 * WMON);
        ChogCreditPool.AccountData memory after_ = pool.accountData(k);
        assertEq(after_.collateralValue, before_.collateralValue);
        assertEq(after_.borrowPower, before_.borrowPower);
        assertEq(after_.liquidationValue, before_.liquidationValue);
        vm.prank(alice);
        vm.expectPartialRevert(ChogCreditPool.BorrowLimitExceeded.selector);
        pool.borrow(k, before_.borrowPower + 1);
    }

    function test_whileIndebted_itCanAlwaysBeWithdrawn() external {
        _holdChog(1_000 * WMON);
        uint256 power = pool.accountData(k).borrowPower;
        _borrow(alice, 1, power); // at the limit
        vm.prank(alice);
        v.withdrawERC20(address(chogToken), 1_000 * WMON, alice); // free, needs no price
        assertEq(chogToken.balanceOf(alice), 1_000 * WMON);
        // and the collateral is still locked
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        v.withdrawERC20(address(wmon), 1 * WMON, alice);
    }

    function test_withdrawing_itNeedsNoPriceEvenWhenOraclesAreDown() external {
        _holdChog(1_000 * WMON);
        _borrow(alice, 1, 100 * USDC);
        oracle.setDown(true);
        vm.prank(alice);
        v.withdrawERC20(address(chogToken), 1_000 * WMON, alice);
    }

    function test_holdingIt_keepsTheChogInTheVault_untilItIsTakenOut() external {
        // empty the WMON first so only the held token remains
        vm.startPrank(alice);
        v.withdrawERC20(address(wmon), 1_000 * WMON, alice);
        vm.stopPrank();
        _holdChog(10 * WMON);
        assertFalse(v.isEmpty());
        vm.prank(alice);
        vm.expectRevert();
        escrow.release(address(chog), 1, alice);
        vm.startPrank(alice);
        v.withdrawERC20(address(chogToken), 10 * WMON, alice);
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), alice);
    }

    function test_itTravelsWithThePackageSale() external {
        _holdChog(777 * WMON);
        AccountTransferCoordinator coord = AccountTransferCoordinator(escrow.coordinator());
        (address buyer, uint256 buyerPk) = makeAddrAndKey("chogBuyer");
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
        vm.prank(buyer);
        v.withdrawERC20(address(chogToken), 777 * WMON, buyer);
        assertEq(chogToken.balanceOf(buyer), 777 * WMON, "the held token went with the Chog");
    }

    function test_aTokenNobodyAllowed_isStillRefused() external {
        TestToken stray = new TestToken("Stray", "STR", 18);
        stray.mint(alice, 1e18);
        vm.startPrank(alice);
        stray.approve(address(v), 1e18);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.TokenNotAllowed.selector, address(stray)));
        v.depositERC20(address(stray), 1e18);
        vm.stopPrank();
    }
}
