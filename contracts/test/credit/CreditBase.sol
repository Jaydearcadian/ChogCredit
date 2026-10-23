// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditFactory} from "../../src/credit/ChogCreditFactory.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {MockChogGenesis} from "../../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";
import {MockOracle} from "../../src/mocks/MockOracles.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

/// @dev Shared fixture. Prices: 1 WMON = 2 USDC, 1 BTC = 60,000 USDC. Defaults: WMON ltv 50%, threshold 75%, bonus 5%;
///      BTC ltv 70%, threshold 80%, bonus 5%; close factor 50%; dust 10 USDC; rates 2% + 4% to 80% util + 60% beyond.
abstract contract CreditBase is Test {
    MockChogGenesis internal chog;
    MockUSDC public usdc;
    TestToken public wmon;
    TestToken internal btc;
    MockOracle public oracle;

    ChogCreditFactory internal factory;
    ChogAccountRegistry internal registry;
    ChogCreditEscrow internal escrow;
    ChogCreditPool public pool;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal lender = address(0x1E4D3);
    address internal lender2 = address(0x1E4D4);
    address internal liquidator = address(0x11C);

    uint256 internal constant USDC = 1e6;
    uint256 internal constant WMON = 1e18;

    function setUp() public virtual {
        chog = new MockChogGenesis(address(this));
        for (uint256 i = 1; i <= 8; i++) {
            chog.mint(i <= 4 ? alice : bob, i);
        }
        usdc = new MockUSDC();
        wmon = new TestToken("Wrapped MON", "WMON", 18);
        btc = new TestToken("Wrapped BTC", "WBTC", 8);
        oracle = new MockOracle();
        oracle.setPrice(address(wmon), 2 * USDC);
        oracle.setPrice(address(btc), 60_000 * USDC);
        _deploy(_poolConfig(), _collaterals(false));
    }

    // ---- configuration helpers (override pieces per test)
    function _poolConfig() internal view returns (ChogCreditPool.PoolConfig memory c) {
        c = ChogCreditPool.PoolConfig({
            loanToken: address(usdc),
            oracle: address(oracle),
            closeFactorBps: 5_000,
            dustDebt: 10 * USDC,
            supplyCap: 1_000_000 * USDC,
            borrowCap: 500_000 * USDC,
            accountDebtCap: 100_000 * USDC,
            baseRateBps: 200,
            slope1Bps: 400,
            slope2Bps: 6_000,
            optimalUtilBps: 8_000
        });
    }

    function _noLp() internal pure returns (ChogCreditPool.LpConfig memory lp) {}

    /// @dev Override to allow more tokens in vaults that are not collateral; the default is none.
    function _extraTokens() internal virtual returns (address[] memory) {
        return new address[](0);
    }

    /// @dev Override to enable Uniswap V3 positions; the default is none.
    function _lpConfig() internal virtual returns (ChogCreditPool.LpConfig memory) {
        return _noLp();
    }

    function _collaterals(bool withBtc) internal view returns (ChogCreditPool.CollateralConfig[] memory cols) {
        cols = new ChogCreditPool.CollateralConfig[](withBtc ? 2 : 1);
        cols[0] = ChogCreditPool.CollateralConfig(address(wmon), 5_000, 7_500, 500, type(uint256).max);
        if (withBtc) cols[1] = ChogCreditPool.CollateralConfig(address(btc), 7_000, 8_000, 500, type(uint256).max);
    }

    function _deploy(ChogCreditPool.PoolConfig memory pc, ChogCreditPool.CollateralConfig[] memory cols) internal {
        address[] memory collections = new address[](1);
        collections[0] = address(chog);
        factory = new ChogCreditFactory(
            ChogCreditFactory.Params({
                collections: collections,
                extraTokens: _extraTokens(),
                rescuer: address(0),
                pool: pc,
                collaterals: cols,
                lp: _lpConfig()
            })
        );
        registry = factory.registry();
        escrow = ChogCreditEscrow(address(registry.escrow()));
        pool = factory.pool();
    }

    // ---- actions
    function _supply(address who, uint256 amount) internal returns (uint256 shares) {
        deal(address(usdc), who, usdc.balanceOf(who) + amount);
        vm.startPrank(who);
        usdc.approve(address(pool), amount);
        shares = pool.supply(amount);
        vm.stopPrank();
    }

    function _key(uint256 id) internal view returns (bytes32) {
        return registry.accountKey(address(chog), id);
    }

    /// @dev Open, escrow and fund an account with `amount` WMON.
    function _fund(address who, uint256 id, uint256 amount) internal returns (AccountVault v) {
        vm.startPrank(who);
        v = AccountVault(registry.createAccount(address(chog), id));
        chog.safeTransferFrom(who, address(escrow), id);
        vm.stopPrank();
        _deposit(who, id, address(wmon), amount);
    }

    function _deposit(address who, uint256 id, address token, uint256 amount) internal {
        AccountVault v = AccountVault(registry.vaultOf(address(chog), id));
        TestToken(token).mint(who, amount);
        vm.startPrank(who);
        TestToken(token).approve(address(v), amount);
        v.depositERC20(token, amount);
        vm.stopPrank();
    }

    function _borrow(address who, uint256 id, uint256 amount) internal {
        bytes32 k = _key(id);
        vm.prank(who);
        pool.borrow(k, amount);
    }

    function _liquidate(address who, uint256 id, uint256 amount) internal returns (uint256 repaid) {
        bytes32 k = _key(id);
        deal(address(usdc), who, usdc.balanceOf(who) + amount);
        vm.startPrank(who);
        usdc.approve(address(pool), amount);
        repaid = pool.liquidate(k, amount);
        vm.stopPrank();
    }
}
