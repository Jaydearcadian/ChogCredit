// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {ChogCreditFactory} from "../../src/credit/ChogCreditFactory.sol";

/// @dev Priority access: above a utilization line, only vaults open for a minimum age may borrow. It allocates capacity;
///      it never changes a limit or a rate.
contract PriorityAccessTest is CreditBase {
    function setUp() public override {
        super.setUp();
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.priorityUtilBps = 5_000; // 50%
        pc.priorityMinAge = 1 days;
        _deploy(pc, _collaterals(false));
        _supply(lender, 10_000 * USDC);
    }

    function test_belowTheLine_anyVaultCanBorrow() external {
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        pool.borrow(k, 4_000 * USDC); // 40% after: under the line, a brand new vault is fine
        assertEq(pool.debtOf(k), 4_000 * USDC);
    }

    function test_aboveTheLine_aNewVaultIsHeldBack_aTenuredOneIsNot() external {
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        assertTrue(pool.priorityRestricted(k, 6_000 * USDC), "the view agrees");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.PriorityAccessOnly.selector, 6_000, 1 days, 0));
        pool.borrow(k, 6_000 * USDC);

        vm.warp(block.timestamp + 1 days);
        assertFalse(pool.priorityRestricted(k, 6_000 * USDC));
        vm.prank(alice);
        pool.borrow(k, 6_000 * USDC);
        assertEq(pool.debtOf(k), 6_000 * USDC);
    }

    function test_oneSecondShortOfTheAge_isStillHeldBack() external {
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        vm.warp(block.timestamp + 1 days - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditPool.PriorityAccessOnly.selector, 6_000, 1 days, 1 days - 1));
        pool.borrow(k, 6_000 * USDC);
    }

    function test_theLineIsInclusive_exactlyAtItIsAllowed() external {
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        pool.borrow(k, 5_000 * USDC); // exactly 50%
        assertEq(pool.debtOf(k), 5_000 * USDC);
    }

    function test_repayingBringsTheLineBack_soANewVaultCanBorrowAgain() external {
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        pool.borrow(k, 6_000 * USDC); // tenured: allowed, pool now at 60%
        vm.prank(bob);
        registry.createAccount(address(chog), 6); // a vault opened just now
        bytes32 k6 = _key(6);
        assertTrue(pool.priorityRestricted(k6, 100 * USDC), "held back while the pool is busy");
        deal(address(usdc), alice, 6_000 * USDC);
        vm.startPrank(alice);
        usdc.approve(address(pool), 6_000 * USDC);
        pool.repay(k, 3_500 * USDC);
        vm.stopPrank();
        assertFalse(pool.priorityRestricted(k6, 100 * USDC), "back under the line");
    }

    function test_off_byDefault() external {
        _deploy(_poolConfig(), _collaterals(false)); // priorityUtilBps = 0
        _supply(lender, 10_000 * USDC);
        _fund(alice, 1, 20_000 * WMON);
        bytes32 k = _key(1);
        vm.prank(alice);
        pool.borrow(k, 9_000 * USDC);
        assertFalse(pool.priorityRestricted(k, 500 * USDC));
    }

    function test_badConfig() external {
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.priorityUtilBps = 10_001;
        pc.priorityMinAge = 1 days;
        address[] memory collections = new address[](1);
        collections[0] = address(chog);
        ChogCreditFactory.Params memory p = ChogCreditFactory.Params({
            collections: collections,
            extraTokens: new address[](0),
            rescuer: address(0),
            pool: pc,
            collaterals: _collaterals(false),
            lp: _noLp()
        });
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditFactory(p);

        p.pool.priorityUtilBps = 9_000;
        p.pool.priorityMinAge = 0; // a line with no age means nothing
        vm.expectRevert(ChogCreditPool.BadConfig.selector);
        new ChogCreditFactory(p);
    }
}
