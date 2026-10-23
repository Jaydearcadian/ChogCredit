// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockOracle} from "../../src/mocks/MockOracles.sol";

/// @dev The testnet price keeper may set prices only. Pausing prices stays with the owner.
contract OracleKeeperTest is Test {
    MockOracle internal oracle;
    address internal keeper = address(0xBEEF);
    address internal stranger = address(0xBAD);
    address internal token = address(0x1234);

    function setUp() public {
        oracle = new MockOracle();
        oracle.setKeeper(keeper);
    }

    function test_keeperCanSetPrices() external {
        vm.prank(keeper);
        oracle.setPrice(token, 21_000);
        assertEq(oracle.pricePerWholeToken(token), 21_000);
    }

    function test_keeperCannotPauseOrAppointOrOwn() external {
        vm.startPrank(keeper);
        vm.expectRevert("owner");
        oracle.setDown(true);
        vm.expectRevert("owner");
        oracle.setKeeper(stranger);
        vm.stopPrank();
    }

    function test_strangersCannotSetPrices() external {
        vm.prank(stranger);
        vm.expectRevert("owner or keeper");
        oracle.setPrice(token, 1);
    }

    function test_ownerStillCan_andCanRemoveTheKeeper() external {
        oracle.setPrice(token, 5);
        oracle.setKeeper(address(0));
        vm.prank(keeper);
        vm.expectRevert("owner or keeper");
        oracle.setPrice(token, 6);
    }
}
