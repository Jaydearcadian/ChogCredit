// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ICreditModule} from "../../src/core/interfaces/IChogAccountRegistry.sol";
import {MockChogGenesis} from "../../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";
import {FeeOnTransferToken, ReentrantToken} from "../../src/mocks/HostileMocks.sol";

/// @notice TEST ONLY. Stands in for the Gate D credit pool.
contract MockCreditModule is ICreditModule {
    mapping(bytes32 => uint256) public debt;
    mapping(bytes32 => bool) public pending;
    bool public broken;

    function setDebt(bytes32 key, uint256 d) external {
        debt[key] = d;
    }

    function setPending(bytes32 key, bool p) external {
        pending[key] = p;
    }

    function setBroken(bool b) external {
        broken = b;
    }

    function debtOf(bytes32 key) external view returns (uint256) {
        require(!broken, "module down");
        return debt[key];
    }

    function hasPendingOperation(bytes32 key) external view returns (bool) {
        require(!broken, "module down");
        return pending[key];
    }
}

abstract contract CoreBase is Test {
    MockChogGenesis internal chog;
    MockUSDC internal usdc;
    FeeOnTransferToken internal feeToken;
    ReentrantToken internal reToken;
    ChogAccountRegistry internal registry;
    ChogCreditEscrow internal escrow;
    MockCreditModule internal module;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);

    function setUp() public virtual {
        chog = new MockChogGenesis(address(this));
        chog.mint(alice, 1);
        chog.mint(alice, 2);
        chog.mint(bob, 532);
        usdc = new MockUSDC();
        feeToken = new FeeOnTransferToken();
        reToken = new ReentrantToken();

        address[] memory cols = new address[](1);
        cols[0] = address(chog);
        address[] memory toks = new address[](3);
        toks[0] = address(usdc);
        toks[1] = address(feeToken);
        toks[2] = address(reToken);
        registry = new ChogAccountRegistry(cols, toks); // this test contract is the binder
        escrow = ChogCreditEscrow(address(registry.escrow()));
        module = new MockCreditModule();
    }

    /// @dev Account opened but the Chog is still in the wallet (cannot hold assets).
    function _openWalletHeld(address who, uint256 tokenId) internal returns (AccountVault v) {
        vm.prank(who);
        v = AccountVault(registry.createAccount(address(chog), tokenId));
    }

    /// @dev Account opened and the Chog deposited into escrow (can hold assets).
    function _open(address who, uint256 tokenId) internal returns (AccountVault v) {
        v = _openWalletHeld(who, tokenId);
        vm.prank(who);
        chog.safeTransferFrom(who, address(escrow), tokenId);
    }

    function _key(uint256 tokenId) internal view returns (bytes32) {
        return registry.accountKey(address(chog), tokenId);
    }
}
