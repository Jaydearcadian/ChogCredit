// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoreBase} from "./CoreBase.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";

contract AccountVaultTest is CoreBase {
    AccountVault internal vault;

    function setUp() public override {
        super.setUp();
        vault = _open(alice, 1); // Chog 1 escrowed, so the vault may hold assets
        deal(address(usdc), alice, 1_000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ---- custody mode: safe by default
    function test_depositRefusedWhileChogIsStillInTheWallet() external {
        AccountVault v = _openWalletHeld(alice, 2);
        vm.startPrank(alice);
        usdc.approve(address(v), type(uint256).max);
        vm.expectRevert(AccountVault.AssetsNotAccepted.selector);
        v.depositERC20(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_escrowedPortfolioCannotBeSoldWithTheNft() external {
        vm.prank(alice);
        vault.depositERC20(address(usdc), 500e6);

        // The Chog is held by escrow, so neither the owner nor an approved marketplace operator can move it.
        vm.prank(alice);
        chog.setApprovalForAll(carol, true);
        vm.prank(carol);
        vm.expectRevert();
        chog.transferFrom(alice, carol, 1);
        vm.prank(alice);
        vm.expectRevert();
        chog.transferFrom(alice, carol, 1);

        assertEq(chog.ownerOf(1), address(escrow));
        vm.prank(carol);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.withdrawERC20(address(usdc), 500e6, carol);
        assertEq(vault.accounted(address(usdc)), 500e6);
    }

    // ---- deposit / withdraw
    function test_depositAndWithdraw_updatesBalancesNonceAndAccounting() external {
        assertEq(vault.stateNonce(), 0);
        assertTrue(vault.isEmpty());
        vm.prank(alice);
        vault.depositERC20(address(usdc), 400e6);
        assertEq(vault.balanceOfToken(address(usdc)), 400e6);
        assertEq(vault.accounted(address(usdc)), 400e6);
        assertEq(vault.nonEmptyTokens(), 1);
        assertFalse(vault.isEmpty());
        assertEq(usdc.balanceOf(alice), 600e6);
        assertEq(vault.stateNonce(), 1);

        vm.prank(alice);
        vault.withdrawERC20(address(usdc), 150e6, bob);
        assertEq(usdc.balanceOf(bob), 150e6);
        assertEq(vault.accounted(address(usdc)), 250e6);
        assertEq(vault.stateNonce(), 2);
        assertFalse(vault.isEmpty());

        vm.prank(alice);
        vault.withdrawERC20(address(usdc), 250e6, bob);
        assertTrue(vault.isEmpty());
        assertEq(vault.nonEmptyTokens(), 0);
    }

    function test_cannotWithdrawMoreThanAccounted() external {
        vm.prank(alice);
        vault.depositERC20(address(usdc), 10e6);
        deal(address(usdc), address(vault), 1_000e6); // donation inflates balanceOf only
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.ExceedsAccounted.selector, 11e6, 10e6));
        vault.withdrawERC20(address(usdc), 11e6, alice);
    }

    function test_nonControllerCannotDepositOrWithdraw() external {
        deal(address(usdc), bob, 10e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.depositERC20(address(usdc), 1e6);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.withdrawERC20(address(usdc), 1, bob);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.sweepUnaccounted(address(usdc), bob);
        vm.stopPrank();
    }

    function test_unsupportedTokenRejected() external {
        MockOther t = new MockOther();
        t.mint(alice, 10);
        vm.startPrank(alice);
        t.approve(address(vault), 10);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.TokenNotAllowed.selector, address(t)));
        vault.depositERC20(address(t), 10);
        vm.stopPrank();
    }

    function test_zeroAmountAndZeroRecipientRevert() external {
        vm.startPrank(alice);
        vm.expectRevert(AccountVault.ZeroAmount.selector);
        vault.depositERC20(address(usdc), 0);
        vm.expectRevert(AccountVault.ZeroAmount.selector);
        vault.withdrawERC20(address(usdc), 0, alice);
        vm.expectRevert(AccountVault.ZeroAddress.selector);
        vault.withdrawERC20(address(usdc), 1, address(0));
        vm.expectRevert(AccountVault.ZeroAddress.selector);
        vault.sweepUnaccounted(address(usdc), address(0));
        vm.stopPrank();
    }

    function test_feeOnTransferTokenRejectedByBalanceDelta() external {
        feeToken.mint(alice, 1_000e18);
        vm.startPrank(alice);
        feeToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.BalanceDeltaMismatch.selector, 100e18, 99e18));
        vault.depositERC20(address(feeToken), 100e18);
        vm.stopPrank();
        assertEq(vault.balanceOfToken(address(feeToken)), 0);
        assertTrue(vault.isEmpty());
    }

    function test_reentrantTokenCannotReenterVault() external {
        reToken.mint(alice, 100e18);
        reToken.arm(address(vault), alice);
        vm.startPrank(alice);
        reToken.approve(address(vault), type(uint256).max);
        vault.depositERC20(address(reToken), 100e18);
        vm.stopPrank();
        assertTrue(reToken.reentryReverted(), "re-entry attempt must revert");
        assertEq(
            bytes4(reToken.reentryReason()),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "stopped by the guard"
        );
        assertEq(vault.balanceOfToken(address(reToken)), 100e18, "re-entry moved nothing");
        assertEq(vault.accounted(address(reToken)), 100e18);
    }

    // ---- unsolicited transfers must not hold the Chog hostage
    function test_unsolicitedTransferIsNotAccountedAndCanBeSwept() external {
        deal(address(usdc), address(this), 5e6);
        usdc.transfer(address(vault), 5e6);
        assertEq(vault.stateNonce(), 0, "no state change without a controller action");
        assertTrue(vault.isEmpty(), "dust cannot make the account look non-empty");
        assertEq(uint8(registry.releaseBlocker(_key(1))), 0, "release still allowed");

        vm.prank(alice);
        vault.sweepUnaccounted(address(usdc), carol);
        assertEq(usdc.balanceOf(carol), 5e6);

        vm.prank(alice);
        vm.expectRevert(AccountVault.NothingToSweep.selector);
        vault.sweepUnaccounted(address(usdc), carol);
    }

    function test_sweepCannotTouchAccountedFunds() external {
        vm.prank(alice);
        vault.depositERC20(address(usdc), 100e6);
        vm.prank(alice);
        vm.expectRevert(AccountVault.NothingToSweep.selector);
        vault.sweepUnaccounted(address(usdc), alice);
        assertEq(vault.balanceOfToken(address(usdc)), 100e6);
    }

    // ---- debt blocks withdrawals
    function test_withdrawBlockedWhileDebtReported_thenAllowed() external {
        registry.bindCreditModule(address(module));
        vm.prank(alice);
        vault.depositERC20(address(usdc), 100e6);

        module.setDebt(_key(1), 3);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.DebtOutstanding.selector, 3));
        vault.withdrawERC20(address(usdc), 1e6, alice);

        module.setBroken(true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.DebtOutstanding.selector, type(uint256).max));
        vault.withdrawERC20(address(usdc), 1e6, alice);

        module.setBroken(false);
        module.setDebt(_key(1), 0);
        vm.prank(alice);
        vault.withdrawERC20(address(usdc), 100e6, alice);
        assertTrue(vault.isEmpty());
    }

    // ---- initialisation
    function test_cannotReinitialiseClone() external {
        vm.expectRevert(AccountVault.AlreadyInitialized.selector);
        vault.initialize(address(registry), bytes32(uint256(5)));
    }

    function test_implementationIsLocked() external {
        AccountVault impl = AccountVault(registry.vaultImplementation());
        vm.expectRevert(AccountVault.AlreadyInitialized.selector);
        impl.initialize(address(this), bytes32(uint256(5)));
    }

    function test_onlyRegistryCanInitialiseAFreshClone() external {
        address clone = _rawClone();
        vm.expectRevert(AccountVault.OnlyRegistry.selector);
        AccountVault(clone).initialize(address(registry), bytes32(uint256(5)));
    }

    function _rawClone() internal returns (address c) {
        address impl = registry.vaultImplementation();
        bytes memory code =
            abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", impl, hex"5af43d82803e903d91602b57fd5bf3");
        assembly {
            c := create(0, add(code, 0x20), mload(code))
        }
        require(c != address(0));
    }

    // ---- fuzz
    function testFuzz_depositWithdrawConservesTokens(uint96 dep, uint96 wd) external {
        dep = uint96(bound(dep, 1, 1_000e6));
        wd = uint96(bound(wd, 1, dep));
        vm.startPrank(alice);
        vault.depositERC20(address(usdc), dep);
        vault.withdrawERC20(address(usdc), wd, bob);
        vm.stopPrank();
        assertEq(vault.balanceOfToken(address(usdc)), dep - wd);
        assertEq(vault.accounted(address(usdc)), dep - wd);
        assertEq(vault.isEmpty(), dep == wd);
        assertEq(usdc.balanceOf(bob), wd);
        assertEq(usdc.balanceOf(alice), 1_000e6 - dep);
    }
}

contract MockOther {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}
