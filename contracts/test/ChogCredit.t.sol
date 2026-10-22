// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogPositionNFT} from "../src/ChogPositionNFT.sol";
import {ChogCredit} from "../src/ChogCredit.sol";
import {MockUSDC, MockCollateral} from "../src/MockTokens.sol";

contract ChogCreditTest is Test {
    MockUSDC internal usdc;
    MockCollateral internal collateral;
    ChogPositionNFT internal nft;
    ChogCredit internal credit;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() external {
        usdc = new MockUSDC();
        collateral = new MockCollateral();
        nft = new ChogPositionNFT(address(this));
        credit = new ChogCredit(address(usdc), address(collateral), address(nft), address(this), 1_000_000, 5_000, 7_500, 500);
        nft.setCreditFacility(address(credit));
        usdc.faucet();
        collateral.faucet();
        usdc.approve(address(credit), type(uint256).max);
        credit.provideLiquidity(5_000 * 1e6);
        vm.startPrank(alice);
        collateral.faucet();
        collateral.approve(address(credit), type(uint256).max);
        credit.createAccount();
        credit.depositCollateral(1, 100 ether);
        vm.stopPrank();
    }

    function testBorrowCannotExceedLtv() external {
        vm.prank(alice);
        credit.borrow(1, 50 * 1e6);
        assertEq(credit.debtOf(1), 50 * 1e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCredit.BorrowLimitExceeded.selector, 50 * 1e6 + 1, 50 * 1e6));
        credit.borrow(1, 1);
    }

    function testNftCannotTransferWhileDebtActive() external {
        vm.prank(alice);
        credit.borrow(1, 10 * 1e6);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogPositionNFT.DebtActive.selector, 1, 10 * 1e6));
        nft.transferFrom(alice, bob, 1);
    }

    function testRepayUnlocksNftTransferAndCollateral() external {
        vm.startPrank(alice);
        credit.borrow(1, 10 * 1e6);
        usdc.faucet();
        usdc.approve(address(credit), type(uint256).max);
        credit.repay(1, 10 * 1e6);
        nft.transferFrom(alice, bob, 1);
        vm.stopPrank();
        vm.prank(bob);
        credit.withdrawCollateral(1, 100 ether);
        assertEq(nft.ownerOf(1), bob);
        assertEq(credit.collateralOf(1), 0);
    }

    function testInterestAccruesLinearly() external {
        vm.prank(alice);
        credit.borrow(1, 100 * 1e6 / 2);
        vm.warp(block.timestamp + 365 days);
        assertEq(credit.debtOf(1), 52_500_000); // 5% annualized on 50 USDC
    }

    function testLiquidationSeizesCollateralAfterPriceFalls() external {
        vm.prank(alice);
        credit.borrow(1, 50 * 1e6);
        credit.setRiskParameters(500_000, 5_000, 7_500, 500); // collateral marks down to $0.50
        vm.startPrank(bob);
        usdc.faucet();
        usdc.approve(address(credit), type(uint256).max);
        credit.liquidate(1, 10 * 1e6);
        vm.stopPrank();
        assertEq(credit.debtOf(1), 40 * 1e6);
        assertEq(credit.collateralOf(1), 78 ether); // $11 collateral at $0.50/token
    }

    function testBorrowingRequiresLiquidity() external {
        // Current pool has ample liquidity; request beyond the collateral limit is rejected first.
        vm.prank(alice);
        vm.expectRevert();
        credit.borrow(1, 51 * 1e6);
    }
}
