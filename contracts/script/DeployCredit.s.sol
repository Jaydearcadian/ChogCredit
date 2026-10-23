// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChogCreditFactory} from "../src/credit/ChogCreditFactory.sol";
import {ChogCreditPool} from "../src/credit/ChogCreditPool.sol";
import {ChogAccountRegistry} from "../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../src/core/ChogCreditEscrow.sol";
import {MockChogGenesis} from "../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../src/mocks/MockTokens.sol";
import {MockOracle} from "../src/mocks/MockOracles.sol";
import {TestToken} from "../src/mocks/TestToken.sol";
import {MockV3Factory, MockV3Pool, MockPositionManager} from "../src/mocks/MockUniswapV3.sol";
import {LpMath} from "../src/credit/lib/LpMath.sol";

/// @notice Deploys the full Chog Credit system (registry, escrow, coordinator, vault implementation, credit pool,
///         bound in one transaction by the factory) with MOCK assets and a MOCK, owner-priced oracle.
///
///   DEPLOY_MODE=local         any chain except 143 and 10143 (e.g. anvil 31337)
///   DEPLOY_MODE=testnet-mock  chain 10143 only
///
/// Mainnet (143) is refused outright. The mock oracle is settable by the deployer: it is the "admin-set price" that
/// the risk register forbids for real funds, so these deployments are test-only by construction.
/// Optional env: WMON_PRICE_USDC (raw USDC per whole mock WMON, default 20000 = $0.02), RESCUER (default none),
/// SEED_CHOGS (mint ids 1..N to the deployer), SOURCE_COMMIT, ENABLE_LP=true (adds a MOCK Uniswap V3 pool and position
/// manager so Uniswap-position collateral can be exercised). Writes deployments/<mode>-<chainid>.json.
contract DeployCredit is Script {
    error MainnetRefused();
    error WrongChainForMode(string mode, uint256 chainId);
    error UnknownMode(string mode);

    struct Deployed {
        string mode;
        string commit;
        address deployer;
        MockChogGenesis chog;
        MockUSDC usdc;
        TestToken wmon;
        TestToken chogToken; // mock $CHOG: held in vaults, never collateral
        MockOracle oracle;
        ChogCreditFactory factory;
        bool lp;
        MockV3Factory v3f;
        MockPositionManager pm;
        MockV3Pool lpPool;
    }

    function run() external {
        Deployed memory d;
        d.mode = vm.envString("DEPLOY_MODE");
        _checkMode(d.mode, block.chainid);
        d.commit = vm.envOr("SOURCE_COMMIT", string("UNSET"));

        vm.startBroadcast();
        (, d.deployer,) = vm.readCallers();
        d.chog = new MockChogGenesis(d.deployer);
        d.usdc = new MockUSDC();
        d.wmon = new TestToken("Mock Wrapped MON", "mWMON", 18);
        d.chogToken = new TestToken("Mock CHOG", "mCHOG", 18);
        d.oracle = new MockOracle();
        d.oracle.setPrice(address(d.wmon), vm.envOr("WMON_PRICE_USDC", uint256(20_000)));
        uint256 seed = vm.envOr("SEED_CHOGS", uint256(0));
        for (uint256 i = 1; i <= seed; i++) {
            d.chog.mint(d.deployer, i);
        }
        d.lp = vm.envOr("ENABLE_LP", false);
        if (d.lp) _deployMockLp(d);
        d.factory = new ChogCreditFactory(_params(d));
        vm.stopBroadcast();

        _verify(d);
        _writeManifest(d);
    }

    function _params(Deployed memory d) internal view returns (ChogCreditFactory.Params memory p) {
        p.collections = new address[](1);
        p.collections[0] = address(d.chog);
        // $CHOG is vault-allowed so it travels with the Chog, but it is not collateral (no liquidity to liquidate into).
        p.extraTokens = new address[](1);
        p.extraTokens[0] = address(d.chogToken);
        p.rescuer = vm.envOr("RESCUER", address(0));
        p.pool = ChogCreditPool.PoolConfig({
            loanToken: address(d.usdc),
            oracle: address(d.oracle),
            closeFactorBps: 5_000,
            dustDebt: 10e6,
            supplyCap: 1_000_000e6,
            borrowCap: 500_000e6,
            accountDebtCap: 100_000e6,
            baseRateBps: 200,
            slope1Bps: 400,
            slope2Bps: 6_000,
            optimalUtilBps: 8_000
        });
        p.collaterals = new ChogCreditPool.CollateralConfig[](1);
        p.collaterals[0] = ChogCreditPool.CollateralConfig(address(d.wmon), 4_000, 6_500, 800, 2_000_000 ether);
        _requirePermittedCollateral(p.collaterals);
        if (d.lp) {
            p.lp.positionManager = address(d.pm);
            p.lp.pools = new ChogCreditPool.LpPoolConfig[](1);
            p.lp.pools[0] = ChogCreditPool.LpPoolConfig(address(d.lpPool), 2_800, 4_550, 500, 200, 50_000e6);
        }
    }

    /// @dev Mock Uniswap V3 factory, pool and position manager. The oracle prices both pool tokens, and the mock pool is
    ///      set to the oracle's own price so positions are priceable from the start.
    function _deployMockLp(Deployed memory d) internal {
        d.oracle.setPrice(address(d.usdc), 1e6);
        d.v3f = new MockV3Factory();
        d.pm = new MockPositionManager(address(d.v3f));
        d.lpPool = MockV3Pool(d.v3f.createPool(address(d.wmon), address(d.usdc), 3000));
        address t0 = d.lpPool.token0();
        address t1 = d.lpPool.token1();
        uint256 s0 = 10 ** TestToken(t0).decimals() * 1e6;
        uint256 s1 = 10 ** TestToken(t1).decimals() * 1e6;
        d.lpPool.setSqrtPrice(LpMath.sqrtPriceFromValues(d.oracle.quote(t0, s0), s0, d.oracle.quote(t1, s1), s1));
    }

    /// @dev The live CHOG token has no liquidation depth (docs/evidence/LIQUIDITY_MODEL.md), so it is never allowed as
    ///      collateral by this script.
    address internal constant CHOG_TOKEN = 0x350035555E10d9AfAF1566AaebfCeD5BA6C27777;

    function _requirePermittedCollateral(ChogCreditPool.CollateralConfig[] memory cols) internal pure {
        for (uint256 i; i < cols.length; ++i) {
            require(cols[i].token != CHOG_TOKEN, "CHOG token is not permitted as collateral");
        }
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

    function _verify(Deployed memory d) internal view {
        ChogAccountRegistry r = d.factory.registry();
        ChogCreditPool pl = d.factory.pool();
        require(r.creditModule() == address(pl), "pool not bound");
        require(r.isCollectionAllowed(address(d.chog)), "collection not allowlisted");
        require(r.isTokenAllowed(address(d.wmon)), "collateral not vault-allowed");
        require(r.isTokenAllowed(address(d.chogToken)), "CHOG token not vault-allowed");
        for (uint256 i; i < pl.collateralCount(); ++i) {
            require(pl.collateralAt(i).token != address(d.chogToken), "CHOG token must not be collateral");
        }
        require(address(pl.registry()) == address(r), "pool wiring");
        require(address(pl.oracle()) == address(d.oracle), "oracle wiring");
        require(d.usdc.decimals() == 6, "usdc decimals");
    }

    function _writeManifest(Deployed memory d) internal {
        ChogAccountRegistry r = d.factory.registry();
        ChogCreditEscrow e = ChogCreditEscrow(address(r.escrow()));
        string memory k = "manifest";
        vm.serializeString(k, "environment", d.mode);
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeString(k, "securityStatus", "TESTNET_UNAUDITED_MOCK_ASSETS_MOCK_ORACLE");
        vm.serializeString(k, "sourceCommit", d.commit);
        vm.serializeAddress(k, "deployer", d.deployer);
        vm.serializeAddress(k, "mockChogGenesis", address(d.chog));
        vm.serializeAddress(k, "mockUsdc", address(d.usdc));
        vm.serializeAddress(k, "mockWmon", address(d.wmon));
        vm.serializeAddress(k, "mockChogToken", address(d.chogToken));
        vm.serializeAddress(k, "mockOracle", address(d.oracle));
        vm.serializeAddress(k, "factory", address(d.factory));
        vm.serializeAddress(k, "registry", address(r));
        vm.serializeAddress(k, "pool", address(d.factory.pool()));
        vm.serializeAddress(k, "escrow", address(e));
        vm.serializeAddress(k, "transferCoordinator", e.coordinator());
        vm.serializeAddress(k, "vaultImplementation", r.vaultImplementation());
        vm.serializeBool(k, "lpEnabled", d.lp);
        vm.serializeAddress(k, "mockPositionManager", address(d.pm));
        vm.serializeAddress(k, "mockUniswapPool", address(d.lpPool));
        vm.serializeBool(k, "mockOraclePricing", true);
        string memory json = vm.serializeBool(k, "mockAssets", true);
        string memory path = string.concat("deployments/credit-", d.mode, "-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("registry ", address(r));
        console2.log("pool     ", address(d.factory.pool()));
        console2.log("manifest ", path);
    }
}
