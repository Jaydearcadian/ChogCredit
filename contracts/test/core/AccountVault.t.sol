// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CoreBase} from "./CoreBase.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";

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

    // ---- claimReceived: payments to the vault address
    function test_claimReceived_countsAPaymentAndBumpsNonce() external {
        deal(address(usdc), address(this), 120e6);
        usdc.transfer(address(vault), 120e6); // anyone can pay the vault
        assertEq(vault.accounted(address(usdc)), 0);
        assertTrue(vault.isEmpty());
        uint256 n0 = vault.stateNonce();

        vm.prank(alice);
        uint256 got = vault.claimReceived(address(usdc));

        assertEq(got, 120e6);
        assertEq(vault.accounted(address(usdc)), 120e6);
        assertEq(vault.nonEmptyTokens(), 1);
        assertFalse(vault.isEmpty());
        assertEq(vault.stateNonce(), n0 + 1);
        assertEq(uint8(registry.releaseBlocker(_key(1))), uint8(ReleaseBlocker.HasAssets), "now blocks release");

        vm.prank(alice);
        vault.withdrawERC20(address(usdc), 120e6, alice); // and it is withdrawable like a deposit
        assertTrue(vault.isEmpty());
    }

    function test_claimReceived_onlyTheExcessOverWhatIsAccounted() external {
        vm.prank(alice);
        vault.depositERC20(address(usdc), 100e6);
        deal(address(usdc), address(vault), usdc.balanceOf(address(vault)) + 30e6);
        vm.prank(alice);
        assertEq(vault.claimReceived(address(usdc)), 30e6);
        assertEq(vault.accounted(address(usdc)), 130e6);
        assertEq(vault.nonEmptyTokens(), 1, "token already counted, not counted twice");
    }

    function test_claimReceived_secondClaimWithNothingNewReverts() external {
        deal(address(usdc), address(vault), 5e6);
        vm.startPrank(alice);
        vault.claimReceived(address(usdc));
        vm.expectRevert(AccountVault.NothingToClaim.selector);
        vault.claimReceived(address(usdc));
        vm.stopPrank();
    }

    function test_claimReceived_strangerCannotClaim() external {
        deal(address(usdc), address(vault), 5e6);
        uint256 n0 = vault.stateNonce();
        vm.prank(bob);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.claimReceived(address(usdc));
        assertEq(vault.stateNonce(), n0, "a stranger cannot bump the nonce");
    }

    function test_claimReceived_refusedWhileChogNotEscrowed() external {
        AccountVault v = _openWalletHeld(alice, 2);
        deal(address(usdc), address(v), 5e6);
        vm.prank(alice);
        vm.expectRevert(AccountVault.AssetsNotAccepted.selector);
        v.claimReceived(address(usdc));
    }

    function test_claimReceived_refusedForATokenOffTheAllowlist() external {
        MockOther t = new MockOther();
        t.mint(address(vault), 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccountVault.TokenNotAllowed.selector, address(t)));
        vault.claimReceived(address(t));
        assertEq(vault.accounted(address(t)), 0, "never counted");
    }

    function test_claimReceived_creditsWhatActuallyArrivedForAFeeToken() external {
        feeToken.mint(address(this), 1_000e18);
        feeToken.transfer(address(vault), 1_000e18);
        uint256 arrived = feeToken.balanceOf(address(vault));
        assertLt(arrived, 1_000e18, "fee was taken in transit");
        vm.prank(alice);
        assertEq(vault.claimReceived(address(feeToken)), arrived);
        assertEq(vault.accounted(address(feeToken)), feeToken.balanceOf(address(vault)));
    }

    function test_claimReceived_paymentSentBeforeTheVaultExistsIsClaimable() external {
        chog.mint(alice, 5);
        address predicted = registry.predictVault(address(chog), 5);
        deal(address(usdc), address(this), 77e6);
        usdc.transfer(predicted, 77e6); // paid to a Chog whose vault is not open yet
        assertEq(predicted.code.length, 0);

        AccountVault v = _open(alice, 5);
        assertEq(address(v), predicted);
        assertEq(usdc.balanceOf(address(v)), 77e6);
        assertTrue(v.isEmpty(), "not counted until claimed");

        vm.prank(alice);
        assertEq(v.claimReceived(address(usdc)), 77e6);
        assertEq(v.accounted(address(usdc)), 77e6);
    }

    /// @dev Any mix of deposits, outside payments, claims and withdrawals keeps `accounted` at or below the balance,
    ///      and `nonEmptyTokens` equal to the number of tokens with an accounted balance.
    function testFuzz_claimReceived_accountingNeverExceedsBalance(uint64[8] calldata amts, uint8[8] calldata ops)
        external
    {
        deal(address(usdc), alice, 1e12);
        for (uint256 i; i < 8; i++) {
            uint256 a = uint256(amts[i]) % 1e9 + 1;
            uint8 op = ops[i] % 4;
            if (op == 0) {
                vm.prank(alice);
                vault.depositERC20(address(usdc), a);
            } else if (op == 1) {
                deal(address(usdc), address(vault), usdc.balanceOf(address(vault)) + a); // outside payment
            } else if (op == 2) {
                vm.prank(alice);
                try vault.claimReceived(address(usdc)) {} catch {}
            } else {
                uint256 have = vault.accounted(address(usdc));
                if (have != 0) {
                    vm.prank(alice);
                    vault.withdrawERC20(address(usdc), a > have ? have : a, alice);
                }
            }
            assertLe(vault.accounted(address(usdc)), usdc.balanceOf(address(vault)));
            assertEq(vault.nonEmptyTokens(), vault.accounted(address(usdc)) == 0 ? 0 : 1);
        }
    }

    // ---- debt blocks withdrawals
    function test_withdrawBlockedWhileDebtReported_thenAllowed() external {
        registry.bindCreditModule(address(module));
        vm.prank(alice);
        vault.depositERC20(address(usdc), 100e6);

        module.setDebt(_key(1), 3);
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
        vault.withdrawERC20(address(usdc), 1e6, alice);

        module.setBroken(true);
        vm.prank(alice);
        vm.expectRevert(AccountVault.WithdrawalBlocked.selector);
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

    // ---- seizeCollateral is the liquidation path and nothing else
    function test_seizeCollateral_onlyTheBoundCreditModule() external {
        vm.prank(alice);
        vault.depositERC20(address(usdc), 100e6);

        // not the controller, not a stranger, not the registry, and no module is bound yet
        address[4] memory callers = [alice, bob, address(registry), address(escrow)];
        for (uint256 i; i < callers.length; i++) {
            vm.prank(callers[i]);
            vm.expectRevert(AccountVault.OnlyCreditModule.selector);
            vault.seizeCollateral(address(usdc), 1e6, callers[i]);
        }

        registry.bindCreditModule(address(module));
        vm.prank(alice);
        vm.expectRevert(AccountVault.OnlyCreditModule.selector);
        vault.seizeCollateral(address(usdc), 1e6, alice); // even the owner cannot use the liquidation path

        uint256 nonceBefore = vault.stateNonce();
        vm.prank(address(module));
        vault.seizeCollateral(address(usdc), 40e6, carol);
        assertEq(usdc.balanceOf(carol), 40e6);
        assertEq(vault.accounted(address(usdc)), 60e6);
        assertGt(vault.stateNonce(), nonceBefore, "a seizure voids pending sale acceptances");
        vm.prank(address(module));
        vm.expectRevert(abi.encodeWithSelector(AccountVault.ExceedsAccounted.selector, 61e6, 60e6));
        vault.seizeCollateral(address(usdc), 61e6, carol);
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
