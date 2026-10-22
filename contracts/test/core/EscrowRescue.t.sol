// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoreBase} from "./CoreBase.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {HostileCollection} from "../../src/mocks/HostileMocks.sol";

contract EscrowRescueTest is CoreBase {
    event RescueRequested(address indexed collection, uint256 indexed tokenId, address to, uint256 readyAt);
    event RescueExecuted(address indexed collection, uint256 indexed tokenId, address to);

    function _strand(uint256 id) internal {
        _openWalletHeld(alice, id);
        vm.prank(alice);
        chog.transferFrom(alice, address(escrow), id); // the mistake: no callback, so no record
    }

    function test_rescue_strandedToken_afterDelay_toChosenAddress() external {
        _strand(1);
        uint256 readyAt = block.timestamp + 3 days;
        vm.expectEmit(true, true, false, true, address(escrow));
        emit RescueRequested(address(chog), 1, alice, readyAt);
        vm.prank(rescuer);
        escrow.requestRescue(address(chog), 1, alice);

        vm.prank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.RescueNotReady.selector, readyAt));
        escrow.executeRescue(address(chog), 1);

        vm.warp(readyAt);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit RescueExecuted(address(chog), 1, alice);
        vm.prank(rescuer);
        escrow.executeRescue(address(chog), 1);
        assertEq(chog.ownerOf(1), alice);
    }

    function test_rescue_neverTouchesARecordedToken() external {
        _open(alice, 1);
        vm.startPrank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotStranded.selector, address(chog), 1));
        escrow.requestRescue(address(chog), 1, rescuer);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), address(escrow));
        assertEq(escrow.beneficialOwnerOf(_key(1)), alice);
    }

    function test_rescue_cannotTakeATokenThatIsNotInEscrow() external {
        vm.prank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotStranded.selector, address(chog), 1));
        escrow.requestRescue(address(chog), 1, rescuer); // alice still holds it
    }

    function test_rescue_onlyRescuer() external {
        _strand(1);
        vm.startPrank(bob);
        vm.expectRevert(ChogCreditEscrow.NotRescuer.selector);
        escrow.requestRescue(address(chog), 1, bob);
        vm.expectRevert(ChogCreditEscrow.NotRescuer.selector);
        escrow.executeRescue(address(chog), 1);
        vm.expectRevert(ChogCreditEscrow.NotRescuer.selector);
        escrow.cancelRescue(address(chog), 1);
        vm.stopPrank();
    }

    function test_rescue_cancel_andExecuteWithoutRequestReverts() external {
        _strand(1);
        vm.startPrank(rescuer);
        vm.expectRevert(ChogCreditEscrow.NoRescuePending.selector);
        escrow.executeRescue(address(chog), 1);
        vm.expectRevert(ChogCreditEscrow.NoRescuePending.selector);
        escrow.cancelRescue(address(chog), 1);
        escrow.requestRescue(address(chog), 1, alice);
        escrow.cancelRescue(address(chog), 1);
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(ChogCreditEscrow.NoRescuePending.selector);
        escrow.executeRescue(address(chog), 1);
        vm.stopPrank();
    }

    function test_rescue_zeroRecipientReverts() external {
        _strand(1);
        vm.prank(rescuer);
        vm.expectRevert(ChogCreditEscrow.ZeroAddress.selector);
        escrow.requestRescue(address(chog), 1, address(0));
    }

    function test_rescue_worksForUnlistedCollectionTokensToo() external {
        HostileCollection other = new HostileCollection();
        other.mint(alice, 5);
        vm.prank(alice);
        other.transferFrom(alice, address(escrow), 5);
        vm.startPrank(rescuer);
        escrow.requestRescue(address(other), 5, alice);
        vm.warp(block.timestamp + 3 days);
        escrow.executeRescue(address(other), 5);
        vm.stopPrank();
        assertEq(other.ownerOf(5), alice);
    }

    function test_rescue_disabledWhenNoRescuer() external {
        address[] memory cols = new address[](1);
        cols[0] = address(chog);
        ChogAccountRegistry r = new ChogAccountRegistry(cols, new address[](0), address(this), address(0));
        ChogCreditEscrow e = ChogCreditEscrow(address(r.escrow()));
        vm.expectRevert(ChogCreditEscrow.RescueDisabled.selector);
        e.requestRescue(address(chog), 1, alice);
        vm.expectRevert(ChogCreditEscrow.RescueDisabled.selector);
        e.cancelRescue(address(chog), 1);
    }

    function test_rescue_pendingRequestDoesNotBlockAHolderFromNothing() external {
        // Once a stranded token is rescued, the owner can run the normal flow again.
        _strand(1);
        vm.startPrank(rescuer);
        escrow.requestRescue(address(chog), 1, alice);
        vm.warp(block.timestamp + 3 days);
        escrow.executeRescue(address(chog), 1);
        vm.stopPrank();
        vm.prank(alice);
        chog.safeTransferFrom(alice, address(escrow), 1);
        assertEq(escrow.beneficialOwnerOf(_key(1)), alice);
    }
}
