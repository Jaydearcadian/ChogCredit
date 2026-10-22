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
        vault = _open(alice, 1);
        deal(address(usdc), alice, 1_000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ---- custody mode: safe by default
    function test_depositRefusedWhenAssetsNotAccepted_defaultMode() external {
        vm.prank(alice);
        AccountVault v = AccountVault(strictRegistry.createAccount(address(chog), 1));
        vm.startPrank(alice);
        usdc.approve(address(v), type(uint256).max);
        vm.expectRevert(AccountVault.AssetsNotAccepted.selector);
        v.depositERC20(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_walletHeldControlFollowsNftSale_whyEscrowIsRequired() external {
        // Documents the hazard Gate C closes: while the NFT sits in a wallet, selling it hands over the vault.
        vm.prank(alice);
        vault.depositERC20(address(usdc), 500e6);
        vm.prank(alice);
        chog.transferFrom(alice, carol, 1);

        vm.prank(alice);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.withdrawERC20(address(usdc), 500e6, alice);

        vm.prank(carol);
        vault.withdrawERC20(address(usdc), 500e6, carol);
        assertEq(usdc.balanceOf(carol), 500e6);
    }

    // ---- deposit / withdraw
    function test_depositAndWithdraw_updatesBalancesAndNonce() external {
        assertEq(vault.stateNonce(), 0);
        vm.prank(alice);
        vault.depositERC20(address(usdc), 400e6);
        assertEq(vault.balanceOfToken(address(usdc)), 400e6);
        assertEq(usdc.balanceOf(alice), 600e6);
        assertEq(vault.stateNonce(), 1);

        vm.prank(alice);
        vault.withdrawERC20(address(usdc), 150e6, bob);
        assertEq(usdc.balanceOf(bob), 150e6);
        assertEq(vault.balanceOfToken(address(usdc)), 250e6);
        assertEq(vault.stateNonce(), 2);
    }

    function test_nonControllerCannotDepositOrWithdraw() external {
        deal(address(usdc), bob, 10e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.depositERC20(address(usdc), 1e6);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.withdrawERC20(address(usdc), 1, bob);
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
    }

    function test_unsolicitedTransferIsNotAccounted() external {
        deal(address(usdc), address(this), 5e6);
        usdc.transfer(address(vault), 5e6);
        assertEq(vault.stateNonce(), 0, "no state change without a controller action");
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
        // A fresh clone not yet initialised by the registry rejects any other initialiser.
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
