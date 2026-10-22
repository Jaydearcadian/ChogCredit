// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChogPositionNFT} from "../src/legacy/ChogPositionNFT.sol";
import {ChogCredit} from "../src/legacy/ChogCredit.sol";
import {MockUSDC, MockCollateral} from "../src/mocks/MockTokens.sol";

/// @dev For Monad testnet. Set DEPLOY_MOCK_TOKENS=true to deploy public-faucet mock assets.
///      Do not use mock assets on mainnet. Deployment is not a security audit.
contract Deploy is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        bool useMocks = vm.envBool("DEPLOY_MOCK_TOKENS");
        uint256 price = vm.envOr("COLLATERAL_PRICE_USDC_6DP", uint256(1_000_000));
        uint256 maxLtv = vm.envOr("MAX_LTV_BPS", uint256(5_000));
        uint256 liquidationThreshold = vm.envOr("LIQUIDATION_THRESHOLD_BPS", uint256(7_500));
        uint256 annualRate = vm.envOr("ANNUAL_INTEREST_BPS", uint256(500));

        vm.startBroadcast(privateKey);
        address usdcAddress;
        address collateralAddress;
        if (useMocks) {
            usdcAddress = address(new MockUSDC());
            collateralAddress = address(new MockCollateral());
        } else {
            usdcAddress = vm.envAddress("USDC_ADDRESS");
            collateralAddress = vm.envAddress("COLLATERAL_TOKEN_ADDRESS");
        }
        ChogPositionNFT nft = new ChogPositionNFT(deployer);
        ChogCredit credit = new ChogCredit(
            usdcAddress, collateralAddress, address(nft), deployer, price, maxLtv, liquidationThreshold, annualRate
        );
        nft.setCreditFacility(address(credit));
        vm.stopBroadcast();

        console2.log("NETWORK chainId:", block.chainid);
        console2.log("USDC / mock USDC:", usdcAddress);
        console2.log("Collateral / mock collateral:", collateralAddress);
        console2.log("ChogPositionNFT:", address(nft));
        console2.log("ChogCredit:", address(credit));
        console2.log("Owner/admin:", deployer);
    }
}
