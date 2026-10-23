// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ChogAccountRegistry} from "../src/core/ChogAccountRegistry.sol";
import {ChogCreditEscrow} from "../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../src/core/AccountVault.sol";
import {ChogCreditPool} from "../src/credit/ChogCreditPool.sol";
import {MockChogGenesis} from "../src/mocks/MockChogGenesis.sol";
import {MockUSDC} from "../src/mocks/MockTokens.sol";
import {TestToken} from "../src/mocks/TestToken.sol";
import {MockPositionManager} from "../src/mocks/MockUniswapV3.sol";

/// @notice End-to-end credit flow with real transactions against a DeployCredit deployment (mock assets only):
/// lend, open + escrow a Chog, deposit collateral, borrow, repay, withdraw, release, redeem.
/// Reads the manifest named by MANIFEST; the signer must hold Chog SMOKE_TOKEN (default 1).
contract SmokeCredit is Script {
    struct Ctx {
        MockChogGenesis chog;
        MockUSDC usdc;
        TestToken wmon;
        ChogAccountRegistry registry;
        ChogCreditEscrow escrow;
        ChogCreditPool pool;
        address me;
        uint256 id;
        bytes32 key;
        bool lp;
        MockPositionManager pm;
        address lpPool;
    }

    function run() external {
        Ctx memory c;
        string memory json = vm.readFile(vm.envString("MANIFEST"));
        require(vm.parseJsonUint(json, ".chainId") == block.chainid, "manifest is for another chain");
        require(vm.parseJsonBool(json, ".mockAssets"), "smoke test is for mock deployments only");
        c.chog = MockChogGenesis(vm.parseJsonAddress(json, ".mockChogGenesis"));
        c.usdc = MockUSDC(vm.parseJsonAddress(json, ".mockUsdc"));
        c.wmon = TestToken(vm.parseJsonAddress(json, ".mockWmon"));
        c.registry = ChogAccountRegistry(vm.parseJsonAddress(json, ".registry"));
        c.escrow = ChogCreditEscrow(vm.parseJsonAddress(json, ".escrow"));
        c.pool = ChogCreditPool(vm.parseJsonAddress(json, ".pool"));
        require(address(c.pool).code.length > 0, "manifest addresses have no code: the deployment did not happen");
        c.lp = vm.parseJsonBool(json, ".lpEnabled");
        if (c.lp) {
            c.pm = MockPositionManager(vm.parseJsonAddress(json, ".mockPositionManager"));
            c.lpPool = vm.parseJsonAddress(json, ".mockUniswapPool");
        }
        c.id = vm.envOr("SMOKE_TOKEN", uint256(1));
        c.key = c.registry.accountKey(address(c.chog), c.id);

        vm.startBroadcast();
        (, c.me,) = vm.readCallers();
        require(c.chog.ownerOf(c.id) == c.me, "signer does not hold the smoke token");
        _flow(c);
        vm.stopBroadcast();
        console2.log("CREDIT SMOKE OK for token", c.id);
    }

    function _flow(Ctx memory c) internal {
        // lender side
        c.usdc.faucet();
        c.usdc.approve(address(c.pool), 5_000e6);
        uint256 shares = c.pool.supply(5_000e6);

        // borrower side
        AccountVault vault = AccountVault(c.registry.createAccount(address(c.chog), c.id));
        c.chog.safeTransferFrom(c.me, address(c.escrow), c.id);
        c.wmon.mint(c.me, 100_000e18);
        c.wmon.approve(address(vault), 100_000e18);
        vault.depositERC20(address(c.wmon), 100_000e18); // 100,000 mWMON at $0.02 = $2,000; 40% LTV
        ChogCreditPool.AccountData memory d = c.pool.accountData(c.key);
        require(d.priceOk && d.borrowPower == 800e6, "unexpected borrowing power");

        c.pool.borrow(c.key, 500e6);
        require(c.pool.debtOf(c.key) == 500e6, "debt not recorded");
        // cannot leave with debt outstanding
        require(!c.registry.withdrawAllowed(c.key, address(c.wmon), 100_000e18), "full withdrawal must be refused");

        c.usdc.approve(address(c.pool), type(uint256).max);
        c.pool.repay(c.key, type(uint256).max);
        require(c.pool.debtOf(c.key) == 0, "not repaid");

        vault.withdrawERC20(address(c.wmon), 100_000e18, c.me);
        c.escrow.release(address(c.chog), c.id, c.me);
        require(c.chog.ownerOf(c.id) == c.me, "Chog not returned");
        c.pool.redeem(shares);
        if (c.lp) _lpFlow(c);
    }

    /// @dev Uniswap position as collateral: open an account, deposit a (mock) position, borrow against it, repay and take
    ///      it back out. Uses the next Chog id so the token flow above is unaffected.
    function _lpFlow(Ctx memory c) internal {
        uint256 id = c.id + 1;
        bytes32 key = c.registry.accountKey(address(c.chog), id);
        require(c.chog.ownerOf(id) == c.me, "LP flow needs the signer to hold the next token too");
        c.usdc.faucet();
        c.usdc.approve(address(c.pool), 5_000e6);
        uint256 shares = c.pool.supply(5_000e6);

        AccountVault vault = AccountVault(c.registry.createAccount(address(c.chog), id));
        c.chog.safeTransferFrom(c.me, address(c.escrow), id);
        uint256 pos = c.pm.mint(c.me, c.lpPool, -887_220, 887_220, 1_000_000_000_000_000);
        c.pm.approve(address(vault), pos);
        vault.depositPosition(pos);
        require(c.pm.ownerOf(pos) == address(vault), "vault does not own the position");

        ChogCreditPool.AccountData memory d = c.pool.accountData(key);
        require(d.priceOk && d.borrowPower > 0, "position adds no borrowing power");
        uint256 amt = d.borrowPower / 2;
        c.pool.borrow(key, amt);
        require(c.pool.debtOf(key) == amt, "LP debt not recorded");
        require(!c.registry.positionWithdrawAllowed(key, pos), "position must stay while it backs the loan");

        c.usdc.approve(address(c.pool), type(uint256).max);
        c.pool.repay(key, type(uint256).max);
        vault.withdrawPosition(pos, c.me);
        require(c.pm.ownerOf(pos) == c.me, "position not returned");
        c.escrow.release(address(c.chog), id, c.me);
        c.pool.redeem(shares);
    }
}
