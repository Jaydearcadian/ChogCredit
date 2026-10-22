// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoreBase} from "./CoreBase.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {IChogAccountRegistry, AccountInfo} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {HostileCollection} from "../../src/mocks/HostileMocks.sol";

contract ChogAccountRegistryTest is CoreBase {
    function test_createAccount_returnsPredictedVaultAndRecordsInfo() external {
        address predicted = registry.predictVault(address(chog), 1);
        bytes32 key = registry.accountKey(address(chog), 1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit IChogAccountRegistry.AccountCreated(key, address(chog), 1, predicted, alice);
        AccountVault v = _open(alice, 1);

        assertEq(address(v), predicted);
        assertEq(registry.vaultOf(address(chog), 1), predicted);
        AccountInfo memory info = registry.accountInfo(key);
        assertEq(info.collection, address(chog));
        assertEq(info.tokenId, 1);
        assertEq(info.vault, predicted);
        assertEq(address(v.registry()), address(registry));
        assertEq(v.key(), key);
    }

    function test_noSecondIdentityNftIsMinted() external {
        _open(alice, 1);
        assertEq(chog.totalSupply(), 3, "supply unchanged: no position NFT minted");
        assertEq(chog.ownerOf(1), alice, "the original Chog stays with the user");
    }

    function test_duplicateAccountReverts() external {
        AccountVault v = _open(alice, 1);
        bytes32 key = registry.accountKey(address(chog), 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.AccountExists.selector, key, address(v)));
        registry.createAccount(address(chog), 1);
    }

    function test_nonOwnerCannotCreate() external {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.NotTokenOwner.selector, address(chog), 1, bob));
        registry.createAccount(address(chog), 1);
    }

    function test_nonexistentTokenReverts() external {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.NotTokenOwner.selector, address(chog), 999, alice));
        registry.createAccount(address(chog), 999);
    }

    function test_unlistedCollectionRejected_evenIfItLooksLikeChog() external {
        HostileCollection fake = new HostileCollection();
        fake.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.CollectionNotAllowed.selector, address(fake)));
        registry.createAccount(address(fake), 1);
    }

    function test_zeroAndEoaCollectionRejected() external {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.CollectionNotAllowed.selector, address(0)));
        registry.createAccount(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.CollectionNotAllowed.selector, bob));
        registry.createAccount(bob, 1);
        vm.stopPrank();
    }

    function test_keyDependsOnChainCollectionAndToken() external {
        bytes32 k1 = registry.accountKey(address(chog), 1);
        assertEq(k1, keccak256(abi.encode(block.chainid, address(chog), uint256(1))));
        assertTrue(k1 != registry.accountKey(address(chog), 2));
        assertTrue(k1 != registry.accountKey(address(usdc), 1));
        vm.chainId(12345);
        assertTrue(k1 != registry.accountKey(address(chog), 1), "chain id is part of the key");
    }

    function testFuzz_keysAreUniquePerPair(address c1, uint256 t1, address c2, uint256 t2) external view {
        bytes32 a = registry.accountKey(c1, t1);
        bytes32 b = registry.accountKey(c2, t2);
        if (c1 == c2 && t1 == t2) assertEq(a, b);
        else assertTrue(a != b);
    }

    function test_isController_followsLiveOwner() external {
        _open(alice, 1);
        bytes32 key = registry.accountKey(address(chog), 1);
        assertTrue(registry.isController(key, alice));
        assertFalse(registry.isController(key, bob));
        assertFalse(registry.isController(key, address(0)));
        vm.prank(alice);
        chog.transferFrom(alice, bob, 1);
        assertFalse(registry.isController(key, alice));
        assertTrue(registry.isController(key, bob));
    }

    function test_isController_unknownAccountIsFalse() external view {
        assertFalse(registry.isController(bytes32(uint256(7)), alice));
    }

    function test_accountInfo_unknownReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.UnknownAccount.selector, bytes32(uint256(7))));
        registry.accountInfo(bytes32(uint256(7)));
    }

    function test_delegatedEoaCanCreateAndControl() external {
        // EIP-7702-delegated EOAs carry code (0xef0100 || delegate). They are real Chog holders and must work.
        vm.etch(alice, hex"ef010063c0c19a282a1b52b07dd5a65b58948a07dae32b");
        assertGt(alice.code.length, 0);
        _open(alice, 1);
        assertTrue(registry.isController(registry.accountKey(address(chog), 1), alice));
    }

    function test_isController_failsClosedWhenCollectionReverts() external {
        // An allowlisted collection that later misbehaves must not grant control.
        HostileCollection h = new HostileCollection();
        h.mint(alice, 1);
        address[] memory cols = new address[](1);
        cols[0] = address(h);
        ChogAccountRegistry r = new ChogAccountRegistry(cols, new address[](0), false);
        vm.prank(alice);
        r.createAccount(address(h), 1);
        bytes32 key = r.accountKey(address(h), 1);
        assertTrue(r.isController(key, alice));
        h.setRevert(true);
        assertFalse(r.isController(key, alice));
        h.setRevert(false);
        h.setLie(bob);
        assertTrue(r.isController(key, bob), "a lying allowlisted collection is a trust assumption, see docs");
    }

    function test_constructorValidation() external {
        address[] memory none = new address[](0);
        address[] memory one = new address[](1);
        one[0] = address(chog);
        vm.expectRevert(IChogAccountRegistry.EmptyAllowlist.selector);
        new ChogAccountRegistry(none, none, false);

        address[] memory zero = new address[](1);
        vm.expectRevert(IChogAccountRegistry.ZeroAddress.selector);
        new ChogAccountRegistry(zero, none, false);
        vm.expectRevert(IChogAccountRegistry.ZeroAddress.selector);
        new ChogAccountRegistry(one, zero, false);

        address[] memory dup = new address[](2);
        dup[0] = address(chog);
        dup[1] = address(chog);
        vm.expectRevert(abi.encodeWithSelector(IChogAccountRegistry.DuplicateEntry.selector, address(chog)));
        new ChogAccountRegistry(dup, none, false);
    }

    function test_noAdminSurface() external view {
        // The allowlists have no setters: this just pins the intended public surface.
        assertTrue(registry.isCollectionAllowed(address(chog)));
        assertFalse(registry.isCollectionAllowed(address(usdc)));
        assertTrue(registry.isTokenAllowed(address(usdc)));
    }
}
