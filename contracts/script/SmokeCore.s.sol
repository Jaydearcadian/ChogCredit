// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChogAccountRegistry} from "../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../src/core/AccountVault.sol";
import {MockChogGenesis} from "../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../src/mocks/MockTokens.sol";

/// @notice End-to-end smoke flow with real transactions against a deployment from DeployCore (mock assets only):
/// open account, escrow the Chog, deposit USDC, withdraw, release. Reads the manifest named by MANIFEST.
/// The signer must own Chog id SMOKE_TOKEN (default 1); DeployCore with SEED_CHOGS>=1 mints it to the deployer.
contract SmokeCore is Script {
    function run() external {
        string memory json = vm.readFile(vm.envString("MANIFEST"));
        require(vm.parseJsonUint(json, ".chainId") == block.chainid, "manifest is for another chain");
        require(vm.parseJsonBool(json, ".mockAssets"), "smoke test is for mock deployments only");
        MockChogGenesis chog = MockChogGenesis(vm.parseJsonAddress(json, ".mockChogGenesis"));
        MockUSDC usdc = MockUSDC(vm.parseJsonAddress(json, ".mockUsdc"));
        ChogAccountRegistry registry = ChogAccountRegistry(vm.parseJsonAddress(json, ".registry"));
        ChogCreditEscrow escrow = ChogCreditEscrow(vm.parseJsonAddress(json, ".escrow"));
        uint256 id = vm.envOr("SMOKE_TOKEN", uint256(1));
        require(address(registry).code.length > 0, "manifest addresses have no code: the deployment did not happen");
        require(address(chog).code.length > 0 && address(usdc).code.length > 0, "mock assets missing");
        bytes32 key = registry.accountKey(address(chog), id);

        vm.startBroadcast();
        (, address me,) = vm.readCallers();
        require(chog.ownerOf(id) == me, "signer does not hold the smoke token");
        AccountVault vault = AccountVault(registry.createAccount(address(chog), id));
        require(!registry.canAcceptAssets(key), "wallet-held account must not accept assets");

        chog.safeTransferFrom(me, address(escrow), id);
        require(escrow.beneficialOwnerOf(key) == me, "beneficial owner not recorded");
        require(chog.ownerOf(id) == address(escrow), "escrow does not hold the Chog");
        require(registry.canAcceptAssets(key), "escrowed account must accept assets");

        usdc.faucet();
        usdc.approve(address(vault), 25e6);
        vault.depositERC20(address(usdc), 25e6);
        require(vault.accounted(address(usdc)) == 25e6, "deposit not accounted");
        require(uint8(registry.releaseBlocker(key)) == 2, "release must be blocked by assets"); // HasAssets

        vault.withdrawERC20(address(usdc), 25e6, me);
        require(vault.isEmpty(), "vault should be empty");
        escrow.release(address(chog), id, me);
        require(chog.ownerOf(id) == me, "Chog not returned");
        vm.stopBroadcast();

        console2.log("SMOKE OK for token", id);
        console2.log("vault", address(vault));
    }
}
