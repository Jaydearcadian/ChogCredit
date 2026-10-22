// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {CoreBase} from "./CoreBase.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {HostileCollection} from "../../src/mocks/HostileMocks.sol";

/// @notice TEST ONLY. A beneficial owner that tries every re-entry it can while its Chog is being released.
contract ReentrantBeneficiary is IERC721Receiver {
    ChogCreditEscrow public escrow;
    ChogAccountRegistry public registry;
    IERC721 public chog;
    bool public sawRelease;
    bool public reReleaseFailed;
    bool public reDepositFailed;
    bool public reCreateFailed;

    constructor(ChogAccountRegistry r, IERC721 c) {
        registry = r;
        escrow = ChogCreditEscrow(address(r.escrow()));
        chog = c;
    }

    function open(uint256 id) external {
        registry.createAccount(address(chog), id);
    }

    function deposit(uint256 id) external {
        chog.safeTransferFrom(address(this), address(escrow), id);
    }

    function release(uint256 id) external {
        escrow.release(address(chog), id, address(this));
    }

    function onERC721Received(address, address from, uint256 id, bytes calldata) external returns (bytes4) {
        if (from == address(escrow)) {
            sawRelease = true;
            try escrow.release(address(chog), id, address(this)) {}
            catch {
                reReleaseFailed = true;
            }
            try chog.safeTransferFrom(address(this), address(escrow), id) {}
            catch {
                reDepositFailed = true;
            }
            try registry.createAccount(address(chog), id) {}
            catch {
                reCreateFailed = true;
            }
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ChogCreditEscrowTest is CoreBase {
    event Escrowed(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address beneficialOwner);
    event Released(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address to);

    // ---------------------------------------------------------------- deposit
    function test_deposit_recordsBeneficialOwner_andEmits() external {
        _openWalletHeld(alice, 1);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit Escrowed(_key(1), address(chog), 1, alice);
        vm.prank(alice);
        chog.safeTransferFrom(alice, address(escrow), 1);

        assertEq(escrow.beneficialOwnerOf(_key(1)), alice);
        assertTrue(escrow.isEscrowed(_key(1)));
        assertEq(chog.ownerOf(1), address(escrow));
    }

    function test_deposit_byApprovedOperator_stillCreditsTheOwner() external {
        _openWalletHeld(alice, 1);
        vm.prank(alice);
        chog.setApprovalForAll(bob, true);
        vm.prank(bob);
        chog.safeTransferFrom(alice, address(escrow), 1);
        assertEq(escrow.beneficialOwnerOf(_key(1)), alice, "owner, not the operator");
    }

    function test_deposit_afterSale_creditsTheNewHolder() external {
        _openWalletHeld(alice, 1); // empty account opened by the old holder
        vm.prank(alice);
        chog.transferFrom(alice, bob, 1);
        vm.prank(bob);
        chog.safeTransferFrom(bob, address(escrow), 1);
        assertEq(escrow.beneficialOwnerOf(_key(1)), bob);
        assertFalse(registry.isController(_key(1), alice));
        assertTrue(registry.isController(_key(1), bob));
    }

    function test_deposit_withoutOpenAccount_revertsAndNftStaysPut() external {
        bytes32 key = _key(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.AccountNotOpen.selector, key));
        chog.safeTransferFrom(alice, address(escrow), 1);
        assertEq(chog.ownerOf(1), alice);
    }

    function test_deposit_fromUnlistedCollection_revertsAndNftStaysPut() external {
        HostileCollection fake = new HostileCollection();
        fake.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.CollectionNotAllowed.selector, address(fake)));
        fake.safeTransferFrom(alice, address(escrow), 1);
        assertEq(fake.ownerOf(1), alice);
    }

    function test_onERC721Received_calledDirectlyByAStranger_reverts() external {
        _openWalletHeld(alice, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.CollectionNotAllowed.selector, bob));
        escrow.onERC721Received(bob, alice, 1, "");
        assertFalse(escrow.isEscrowed(_key(1)));
    }

    function test_onERC721Received_forgedByListedCollectionWithoutTransfer_reverts() external {
        // Even a listed collection calling the callback without moving the token cannot create a record.
        _openWalletHeld(alice, 1);
        vm.prank(address(chog));
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotHeld.selector, address(chog), 1));
        escrow.onERC721Received(alice, alice, 1, "");
        assertFalse(escrow.isEscrowed(_key(1)));
    }

    function test_onERC721Received_zeroFromReverts() external {
        _openWalletHeld(alice, 1);
        vm.prank(address(chog));
        vm.expectRevert(ChogCreditEscrow.ZeroAddress.selector);
        escrow.onERC721Received(alice, address(0), 1, "");
    }

    function test_plainTransferFromStrandsTheNft_documentedLimit() external {
        // Using transferFrom instead of safeTransferFrom skips the callback: the token is stuck and unrecorded.
        _openWalletHeld(alice, 1);
        vm.prank(alice);
        chog.transferFrom(alice, address(escrow), 1);
        assertEq(chog.ownerOf(1), address(escrow));
        assertFalse(escrow.isEscrowed(_key(1)));
        assertFalse(registry.isController(_key(1), alice));
        bytes32 key = _key(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotEscrowed.selector, key));
        escrow.release(address(chog), 1, alice);
    }

    function test_escrowHasNoAdminSurface_onlyReleaseMovesTokens() external {
        _open(alice, 1);
        // No owner(), no rescue, no pause: ask the contract and expect nothing to answer.
        (bool ok,) = address(escrow).staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
        (ok,) = address(escrow).call(abi.encodeWithSignature("rescue(address,uint256,address)", address(chog), 1, bob));
        assertFalse(ok);
        assertEq(chog.ownerOf(1), address(escrow));
    }

    // ---------------------------------------------------------------- ordinary transfers cannot bypass
    function test_externalTransfersAreImpossibleWhileEscrowed() external {
        _open(alice, 1);
        vm.prank(alice);
        chog.setApprovalForAll(carol, true); // a marketplace-style operator
        address[3] memory actors = [alice, bob, carol];
        for (uint256 i; i < actors.length; i++) {
            vm.startPrank(actors[i]);
            vm.expectRevert();
            chog.transferFrom(alice, bob, 1);
            vm.expectRevert();
            chog.safeTransferFrom(alice, bob, 1);
            vm.stopPrank();
        }
        assertEq(chog.ownerOf(1), address(escrow));
    }

    // ---------------------------------------------------------------- release
    function test_release_happyPath_returnsNftAndClearsRecord() external {
        _open(alice, 1);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit Released(_key(1), address(chog), 1, bob);
        vm.prank(alice);
        escrow.release(address(chog), 1, bob);

        assertEq(chog.ownerOf(1), bob);
        assertFalse(escrow.isEscrowed(_key(1)));
        assertEq(escrow.beneficialOwnerOf(_key(1)), address(0));
        assertFalse(registry.canAcceptAssets(_key(1)), "assets refused again once the Chog left escrow");
        assertTrue(registry.isController(_key(1), bob), "control falls back to the wallet holder");
        assertFalse(registry.isController(_key(1), alice));
    }

    function test_release_canBeRepeated_reEscrowAfterRelease() external {
        _open(alice, 1);
        vm.prank(alice);
        escrow.release(address(chog), 1, alice);
        vm.prank(alice);
        chog.safeTransferFrom(alice, address(escrow), 1);
        assertEq(escrow.beneficialOwnerOf(_key(1)), alice);
        assertEq(chog.ownerOf(1), address(escrow));
    }

    function test_release_onlyBeneficialOwner() external {
        _open(alice, 1);
        bytes32 key = _key(1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotBeneficialOwner.selector, key, bob));
        escrow.release(address(chog), 1, bob);
        vm.prank(address(escrow));
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotBeneficialOwner.selector, key, address(escrow)));
        escrow.release(address(chog), 1, bob);
        assertEq(chog.ownerOf(1), address(escrow));
    }

    function test_release_notEscrowed_andZeroRecipient() external {
        _openWalletHeld(alice, 1);
        bytes32 key1 = _key(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotEscrowed.selector, key1));
        escrow.release(address(chog), 1, alice);

        _open(alice, 2);
        vm.prank(alice);
        vm.expectRevert(ChogCreditEscrow.ZeroAddress.selector);
        escrow.release(address(chog), 2, address(0));
    }

    function test_release_blockedWhileAccountHoldsAssets() external {
        AccountVault v = _open(alice, 1);
        deal(address(usdc), alice, 1);
        bytes32 key = _key(1);
        vm.startPrank(alice);
        usdc.approve(address(v), 1);
        v.depositERC20(address(usdc), 1); // 1 base unit is enough to block
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.ReleaseBlocked.selector, key, ReleaseBlocker.HasAssets));
        escrow.release(address(chog), 1, alice);

        v.withdrawERC20(address(usdc), 1, alice);
        escrow.release(address(chog), 1, alice);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), alice);
    }

    function test_release_blockedByDebtPendingAndBrokenModule() external {
        registry.bindCreditModule(address(module));
        _open(alice, 1);
        bytes32 key = _key(1);

        module.setDebt(key, 1);
        _expectBlocked(key, ReleaseBlocker.HasDebt);
        module.setDebt(key, 0);

        module.setPending(key, true);
        _expectBlocked(key, ReleaseBlocker.PendingOperation);
        module.setPending(key, false);

        module.setBroken(true);
        _expectBlocked(key, ReleaseBlocker.ModuleUnavailable);
        module.setBroken(false);

        vm.prank(alice);
        escrow.release(address(chog), 1, alice);
        assertEq(chog.ownerOf(1), alice);
    }

    function _expectBlocked(bytes32 key, ReleaseBlocker why) internal {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.ReleaseBlocked.selector, key, why));
        escrow.release(address(chog), 1, alice);
        assertEq(chog.ownerOf(1), address(escrow));
    }

    function test_release_makesNoCallbackIntoTheRecipient() external {
        // release uses transferFrom, so a hostile beneficiary gets no hook to re-enter from.
        ReentrantBeneficiary rb = new ReentrantBeneficiary(registry, IERC721(address(chog)));
        chog.mint(address(rb), 77);
        rb.open(77);
        rb.deposit(77);
        bytes32 key = _key(77);
        assertEq(escrow.beneficialOwnerOf(key), address(rb));

        rb.release(77);

        assertFalse(rb.sawRelease(), "recipient must not be called back");
        assertEq(chog.ownerOf(77), address(rb));
        assertFalse(escrow.isEscrowed(key));
        assertEq(escrow.beneficialOwnerOf(key), address(0));
    }

    function test_release_toNonReceivingContract_works_butIsTheCallersRisk() external {
        _open(alice, 1);
        address sink = address(new NonReceiver());
        vm.prank(alice);
        escrow.release(address(chog), 1, sink); // allowed: no receiver check by design
        assertEq(chog.ownerOf(1), sink);
    }

    function test_delegatedEoa_canDepositAndRelease() external {
        vm.etch(alice, hex"ef010063c0c19a282a1b52b07dd5a65b58948a07dae32b");
        _open(alice, 1);
        assertTrue(registry.isController(_key(1), alice));
        vm.prank(alice);
        escrow.release(address(chog), 1, alice);
        assertEq(chog.ownerOf(1), alice);
    }

    function test_two_chogs_are_independent() external {
        _open(alice, 1);
        _open(alice, 2);
        AccountVault v1 = AccountVault(registry.vaultOf(address(chog), 1));
        AccountVault v2 = AccountVault(registry.vaultOf(address(chog), 2));
        assertTrue(address(v1) != address(v2));
        deal(address(usdc), alice, 10);
        bytes32 key = _key(1);
        vm.startPrank(alice);
        usdc.approve(address(v1), 10);
        v1.depositERC20(address(usdc), 10);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.ReleaseBlocked.selector, key, ReleaseBlocker.HasAssets));
        escrow.release(address(chog), 1, alice);
        escrow.release(address(chog), 2, alice); // the empty one is free to leave
        vm.stopPrank();
        assertEq(chog.ownerOf(2), alice);
        assertEq(chog.ownerOf(1), address(escrow));
    }
}

contract NonReceiver {}
