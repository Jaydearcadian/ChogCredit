// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChogAccountRegistry} from "../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../src/core/ChogCreditEscrow.sol";
import {MockChogGenesis} from "../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../src/mocks/MockTokens.sol";

/// @notice Deploys the Chog Credit core (registry, escrow, coordinator, vault implementation) with MOCK assets.
///
///   DEPLOY_MODE=local         any chain except 143 and 10143 (e.g. anvil 31337)
///   DEPLOY_MODE=testnet-mock  chain 10143 only
///
/// Mainnet (143) is refused outright: no real-funds deployment before the gates in docs/SECURITY_AND_RISK.md pass.
/// Optional env: BINDER (default: deployer), RESCUER (default: none), SEED_CHOGS (mint ids 1..N to the deployer),
/// SOURCE_COMMIT (recorded in the manifest). Writes deployments/<mode>-<chainid>.json.
/// NOTE: the manifest is written while the script runs, including a dry run or a failed broadcast. Treat it as real
/// only if the broadcast succeeded; SmokeCore refuses a manifest whose addresses have no code.
contract DeployCore is Script {
    error MainnetRefused();
    error WrongChainForMode(string mode, uint256 chainId);
    error UnknownMode(string mode);
    error UnexpectedDecimals(uint8 got);

    struct Deployed {
        string mode;
        string commit;
        address deployer;
        address binder;
        address rescuer;
        MockChogGenesis chog;
        MockUSDC usdc;
        ChogAccountRegistry registry;
        ChogCreditEscrow escrow;
    }

    function run() external {
        Deployed memory d;
        d.mode = vm.envString("DEPLOY_MODE");
        _checkMode(d.mode, block.chainid);
        d.rescuer = vm.envOr("RESCUER", address(0));
        d.commit = vm.envOr("SOURCE_COMMIT", string("UNSET"));

        vm.startBroadcast();
        // Ask the VM who is broadcasting. With --private-key this equals msg.sender, but with a keystore or hardware wallet
        // `msg.sender` can be the default sender instead.
        (, d.deployer,) = vm.readCallers();
        d.binder = vm.envOr("BINDER", d.deployer);
        d.chog = new MockChogGenesis(d.deployer);
        d.usdc = new MockUSDC();
        uint256 seed = vm.envOr("SEED_CHOGS", uint256(0));
        for (uint256 i = 1; i <= seed; i++) {
            d.chog.mint(d.deployer, i);
        }
        address[] memory cols = new address[](1);
        cols[0] = address(d.chog);
        address[] memory toks = new address[](1);
        toks[0] = address(d.usdc);
        d.registry = new ChogAccountRegistry(cols, toks, d.binder, d.rescuer);
        vm.stopBroadcast();

        d.escrow = ChogCreditEscrow(address(d.registry.escrow()));
        _verifyWiring(d);
        _writeManifest(d);
    }

    function _checkMode(string memory mode, uint256 chainId) internal pure {
        if (chainId == 143) revert MainnetRefused();
        if (keccak256(bytes(mode)) == keccak256("testnet-mock")) {
            if (chainId != 10143) revert WrongChainForMode(mode, chainId);
        } else if (keccak256(bytes(mode)) == keccak256("local")) {
            if (chainId == 10143) revert WrongChainForMode(mode, chainId);
        } else {
            revert UnknownMode(mode);
        }
    }

    function _verifyWiring(Deployed memory d) internal view {
        if (d.usdc.decimals() != 6) revert UnexpectedDecimals(d.usdc.decimals());
        require(d.registry.isCollectionAllowed(address(d.chog)), "collection not allowlisted");
        require(d.registry.isTokenAllowed(address(d.usdc)), "token not allowlisted");
        require(address(d.escrow.registry()) == address(d.registry), "escrow wiring");
        require(d.registry.binder() == d.binder, "binder");
        require(d.escrow.rescuer() == d.rescuer, "rescuer");
    }

    function _writeManifest(Deployed memory d) internal {
        string memory k = "manifest";
        vm.serializeString(k, "environment", d.mode);
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeString(k, "securityStatus", "TESTNET_UNAUDITED_MOCK_ASSETS");
        vm.serializeString(k, "sourceCommit", d.commit);
        vm.serializeAddress(k, "deployer", d.deployer);
        vm.serializeAddress(k, "mockChogGenesis", address(d.chog));
        vm.serializeAddress(k, "mockUsdc", address(d.usdc));
        vm.serializeAddress(k, "registry", address(d.registry));
        vm.serializeAddress(k, "escrow", address(d.escrow));
        vm.serializeAddress(k, "transferCoordinator", d.escrow.coordinator());
        vm.serializeAddress(k, "vaultImplementation", d.registry.vaultImplementation());
        vm.serializeAddress(k, "binder", d.binder);
        vm.serializeAddress(k, "rescuer", d.rescuer);
        string memory json = vm.serializeBool(k, "mockAssets", true);
        string memory path = string.concat("deployments/", d.mode, "-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("registry            ", address(d.registry));
        console2.log("escrow              ", address(d.escrow));
        console2.log("transferCoordinator ", d.escrow.coordinator());
        console2.log("manifest            ", path);
    }
}
