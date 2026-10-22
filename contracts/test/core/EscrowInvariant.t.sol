// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {MockChogGenesis} from "../../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";

/// @dev Random sequences of every user action across 3 actors and 3 Chogs. Reverting calls are skipped, not failures.
contract EscrowHandler is Test {
    MockChogGenesis public chog;
    MockUSDC public usdc;
    ChogAccountRegistry public registry;
    ChogCreditEscrow public escrow;
    address[3] public actors;
    uint256[3] internal _pks = [uint256(0xA1), 0xB2, 0xC3];
    AccountTransferCoordinator public coord;
    uint256 public ghostSales;
    uint256 internal _salt;
    uint256[3] public ids = [uint256(1), 2, 3];
    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(MockChogGenesis c, MockUSDC u, ChogAccountRegistry r) {
        chog = c;
        usdc = u;
        registry = r;
        escrow = ChogCreditEscrow(address(r.escrow()));
        coord = AccountTransferCoordinator(escrow.coordinator());
        for (uint256 i; i < 3; i++) {
            actors[i] = vm.addr(_pks[i]);
        }
    }

    function _a(uint256 s) internal view returns (address) {
        return actors[s % 3];
    }

    function _id(uint256 s) internal view returns (uint256) {
        return ids[s % 3];
    }

    function openAccount(uint256 a, uint256 i) external {
        vm.prank(_a(a));
        try registry.createAccount(address(chog), _id(i)) {} catch {}
    }

    function depositChog(uint256 a, uint256 i) external {
        address who = _a(a);
        vm.prank(who);
        try chog.safeTransferFrom(who, address(escrow), _id(i)) {} catch {}
    }

    function plainTransferToEscrow(uint256 a, uint256 i) external {
        // the dangerous misuse: skips the callback. Allowed to happen; invariants must still hold for recorded state.
        address who = _a(a);
        vm.prank(who);
        try chog.transferFrom(who, address(escrow), _id(i)) {} catch {}
    }

    function walletTransfer(uint256 a, uint256 b, uint256 i) external {
        address from = _a(a);
        vm.prank(from);
        try chog.transferFrom(from, _a(b), _id(i)) {} catch {}
    }

    function release(uint256 a, uint256 i, uint256 to) external {
        vm.prank(_a(a));
        try escrow.release(address(chog), _id(i), _a(to)) {} catch {}
    }

    function depositToken(uint256 a, uint256 i, uint256 amt) external {
        address v = registry.vaultOf(address(chog), _id(i));
        if (v == address(0)) return;
        amt = bound(amt, 1, 1_000e6);
        address who = _a(a);
        deal(address(usdc), who, amt);
        vm.startPrank(who);
        usdc.approve(v, amt);
        try AccountVault(v).depositERC20(address(usdc), amt) {
            ghostDeposited += amt;
        } catch {}
        vm.stopPrank();
    }

    function withdrawToken(uint256 a, uint256 i, uint256 amt) external {
        address v = registry.vaultOf(address(chog), _id(i));
        if (v == address(0)) return;
        amt = bound(amt, 1, 1_000e6);
        vm.prank(_a(a));
        try AccountVault(v).withdrawERC20(address(usdc), amt, _a(a)) {
            ghostWithdrawn += amt;
        } catch {}
    }

    /// @dev Debt-free signed sale between actors, price 0 so no payment plumbing; reverts are skipped.
    function sell(uint256 i, uint256 b) external {
        uint256 id = _id(i);
        bytes32 key = registry.accountKey(address(chog), id);
        address seller = escrow.beneficialOwnerOf(key);
        if (seller == address(0)) return;
        uint256 bi = b % 3;
        address buyer = actors[bi];
        if (buyer == seller) return;
        AccountTransferCoordinator.Acceptance memory a = AccountTransferCoordinator.Acceptance({
            key: key,
            seller: seller,
            buyer: buyer,
            paymentToken: address(usdc),
            price: 0,
            stateNonce: AccountVault(registry.vaultOf(address(chog), id)).stateNonce(),
            epoch: escrow.epochOf(key),
            deadline: block.timestamp + 1 days,
            salt: ++_salt
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pks[bi], coord.hashAcceptance(a));
        vm.prank(seller);
        try coord.executeSale(a, abi.encodePacked(r, s, v)) {
            ++ghostSales;
        } catch {}
    }

    function rescue(uint256 i) external {
        // the rescuer tries to pull any token out: it must only ever succeed for unrecorded (stranded) tokens
        uint256 id = _id(i);
        vm.startPrank(RESCUER);
        try escrow.requestRescue(address(chog), id, RESCUER) {
            vm.warp(block.timestamp + 3 days);
            try escrow.executeRescue(address(chog), id) {} catch {}
        } catch {}
        vm.stopPrank();
    }

    function donate(uint256 i, uint256 amt) external {
        address v = registry.vaultOf(address(chog), _id(i));
        if (v == address(0)) return;
        deal(address(usdc), v, usdc.balanceOf(v) + bound(amt, 1, 1_000e6));
    }
}

address constant RESCUER = address(0xBE5C);

contract EscrowInvariantTest is Test {
    MockChogGenesis chog;
    MockUSDC usdc;
    ChogAccountRegistry registry;
    ChogCreditEscrow escrow;
    EscrowHandler handler;

    function setUp() external {
        chog = new MockChogGenesis(address(this));
        usdc = new MockUSDC();
        address[] memory cols = new address[](1);
        cols[0] = address(chog);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        registry = new ChogAccountRegistry(cols, toks, address(this), RESCUER);
        escrow = ChogCreditEscrow(address(registry.escrow()));
        handler = new EscrowHandler(chog, usdc, registry);
        for (uint256 i; i < 3; i++) {
            chog.mint(handler.actors(i), i + 1);
        }
        targetContract(address(handler));
    }

    function invariant_assetsImplyEscrowed() external view {
        for (uint256 i; i < 3; i++) {
            uint256 id = handler.ids(i);
            address v = registry.vaultOf(address(chog), id);
            if (v != address(0) && !AccountVault(v).isEmpty()) {
                assertTrue(escrow.isEscrowed(registry.accountKey(address(chog), id)), "assets without escrow");
            }
        }
    }

    function invariant_escrowRecordMatchesCollectionOwnership() external view {
        for (uint256 i; i < 3; i++) {
            uint256 id = handler.ids(i);
            bytes32 key = registry.accountKey(address(chog), id);
            if (escrow.isEscrowed(key)) {
                assertEq(chog.ownerOf(id), address(escrow), "record without custody");
                assertTrue(escrow.beneficialOwnerOf(key) != address(0));
            }
        }
    }

    function invariant_nonEmptyAccountsNeverLoseTheirChog() external view {
        for (uint256 i; i < 3; i++) {
            uint256 id = handler.ids(i);
            address v = registry.vaultOf(address(chog), id);
            if (v != address(0) && !AccountVault(v).isEmpty()) {
                assertEq(chog.ownerOf(id), address(escrow), "a funded account's Chog left escrow");
            }
        }
    }

    function invariant_accountedNeverExceedsBalance() external view {
        for (uint256 i; i < 3; i++) {
            address v = registry.vaultOf(address(chog), handler.ids(i));
            if (v != address(0)) {
                assertLe(AccountVault(v).accounted(address(usdc)), usdc.balanceOf(v), "accounted > balance");
            }
        }
    }

    function invariant_tokenConservation() external view {
        uint256 sumAccounted;
        for (uint256 i; i < 3; i++) {
            address v = registry.vaultOf(address(chog), handler.ids(i));
            if (v != address(0)) sumAccounted += AccountVault(v).accounted(address(usdc));
        }
        assertEq(sumAccounted, handler.ghostDeposited() - handler.ghostWithdrawn(), "accounting drift");
    }

    function invariant_beneficialOwnerAlwaysControls() external view {
        for (uint256 i; i < 3; i++) {
            bytes32 key = registry.accountKey(address(chog), handler.ids(i));
            address ben = escrow.beneficialOwnerOf(key);
            if (ben != address(0)) assertTrue(registry.isController(key, ben), "beneficial owner lost control");
        }
    }

    /// @dev Guards against a vacuous invariant campaign: the handler's own sale and rescue paths really execute.
    function test_handlerPathsAreNotVacuous() external {
        handler.openAccount(0, 0);
        handler.depositChog(0, 0);
        bytes32 key = registry.accountKey(address(chog), 1);
        address first = handler.actors(0);
        assertEq(escrow.beneficialOwnerOf(key), first);

        handler.sell(0, 1); // actor 0 sells account 1 to actor 1 for free
        assertEq(handler.ghostSales(), 1, "sale did not execute");
        assertEq(escrow.beneficialOwnerOf(key), handler.actors(1));

        // strand token 2 with a plain transferFrom, then let the handler's rescuer recover it
        handler.openAccount(1, 1);
        handler.plainTransferToEscrow(1, 1);
        assertEq(chog.ownerOf(2), address(escrow));
        handler.rescue(1);
        assertEq(chog.ownerOf(2), RESCUER, "stranded token was not rescued");
        assertFalse(escrow.isEscrowed(registry.accountKey(address(chog), 2)));
    }

    function invariant_oneVaultPerKey() external view {
        for (uint256 i; i < 3; i++) {
            uint256 id = handler.ids(i);
            address v = registry.vaultOf(address(chog), id);
            if (v != address(0)) assertEq(v, registry.predictVault(address(chog), id));
        }
    }
}
