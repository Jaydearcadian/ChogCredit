// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockPositionManager, MockV3Factory, MockV3Pool} from "../../src/mocks/MockUniswapV3.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

contract MockPmEnumerableTest is Test {
    MockPositionManager pm;
    MockV3Pool pool;

    function setUp() external {
        MockV3Factory f = new MockV3Factory();
        TestToken a = new TestToken("A", "A", 18);
        TestToken b = new TestToken("B", "B", 6);
        pool = MockV3Pool(f.createPool(address(a), address(b), 3000));
        pm = new MockPositionManager(address(f));
    }

    function test_listsOnlyTheOwnersPositions() external {
        uint256 p1 = pm.mint(address(0xA), address(pool), -60, 60, 1e9);
        uint256 p2 = pm.mint(address(0xB), address(pool), -60, 60, 1e9);
        uint256 p3 = pm.mint(address(0xA), address(pool), -120, 120, 1e9);
        assertEq(pm.balanceOf(address(0xA)), 2);
        assertEq(pm.balanceOf(address(0xB)), 1);
        assertEq(pm.tokenOfOwnerByIndex(address(0xA), 0), p1);
        assertEq(pm.tokenOfOwnerByIndex(address(0xA), 1), p3);
        assertEq(pm.tokenOfOwnerByIndex(address(0xB), 0), p2);
        vm.expectRevert("index out of bounds");
        pm.tokenOfOwnerByIndex(address(0xB), 1);
    }

    function test_aTransferMovesItBetweenLists() external {
        uint256 p1 = pm.mint(address(0xA), address(pool), -60, 60, 1e9);
        vm.prank(address(0xA));
        pm.transferFrom(address(0xA), address(0xC), p1);
        assertEq(pm.balanceOf(address(0xA)), 0);
        assertEq(pm.tokenOfOwnerByIndex(address(0xC), 0), p1);
    }
}
