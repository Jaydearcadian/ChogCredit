// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogFaucet} from "../../src/mocks/ChogFaucet.sol";
import {MockChogGenesis} from "../../src/mocks/MockChogGenesis.sol";

contract ChogFaucetTest is Test {
    MockChogGenesis chog;
    ChogFaucet faucet;

    function setUp() external {
        chog = new MockChogGenesis(address(this));
        faucet = new ChogFaucet(chog, 1968);
        chog.grantRole(chog.MINTER_ROLE(), address(faucet));
    }

    function test_claimGivesTheNextIdOncePerAddress() external {
        vm.prank(address(0xA));
        assertEq(faucet.claim(), 1968);
        assertEq(chog.ownerOf(1968), address(0xA));
        vm.prank(address(0xA));
        vm.expectRevert(ChogFaucet.AlreadyClaimed.selector);
        faucet.claim();
        vm.prank(address(0xB));
        assertEq(faucet.claim(), 1969);
    }

    function test_stopsAtMaxSupply() external {
        vm.prank(address(0xA));
        faucet.claim();
        vm.prank(address(0xB));
        faucet.claim();
        vm.prank(address(0xC));
        vm.expectRevert(ChogFaucet.SoldOut.selector);
        faucet.claim();
    }

    function test_withoutMinterRoleItCannotMint() external {
        ChogFaucet orphan = new ChogFaucet(chog, 5);
        vm.prank(address(0xD));
        vm.expectRevert();
        orphan.claim();
    }
}
