// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {MockChogGenesis} from "../../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";
import {FeeOnTransferToken, ReentrantToken} from "../../src/mocks/HostileMocks.sol";

abstract contract CoreBase is Test {
    MockChogGenesis internal chog;
    MockUSDC internal usdc;
    FeeOnTransferToken internal feeToken;
    ReentrantToken internal reToken;
    ChogAccountRegistry internal registry; // wallet-held deposits ON (Gate B test plumbing only)
    ChogAccountRegistry internal strictRegistry; // default-safe: deposits refused

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
        registry = new ChogAccountRegistry(cols, toks, true);
        strictRegistry = new ChogAccountRegistry(cols, toks, false);
    }

    function _open(address who, uint256 tokenId) internal returns (AccountVault v) {
        vm.prank(who);
        v = AccountVault(registry.createAccount(address(chog), tokenId));
    }
}
