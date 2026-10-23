// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LpBase} from "./LpBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {MockPositionManager} from "../../src/mocks/MockUniswapV3.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";
import {MockOracle} from "../../src/mocks/MockOracles.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

/// @dev Random interleavings of position deposits and withdrawals, token collateral, borrowing, repaying, price moves
///      (the pool sometimes drifting away from the oracle), time and liquidation. Reverting calls are skipped.
contract LpHandler is Test {
    LpBase public t; // gives access to the system under test
    // cached so that no helper makes an external call between a prank and the call it is meant for
    ChogCreditPool public pool_;
    MockPositionManager public pm_;
    TestToken public wmon_;
    MockUSDC public usdc_;

    address[2] public owners;
    bytes32[2] public keys;
    AccountVault[2] public vaults;
    uint256[] public allPositions;
    mapping(uint256 => address) public lastHolder; // the account that deposited it

    bool public ghostViolation;
    uint256 public okBorrows;
    uint256 public okDeposits;
    uint256 public okWithdraws;
    uint256 public okLiquidations;
    uint256 public okUnwinds;

    constructor(LpBase t_, address[2] memory owners_, bytes32[2] memory keys_, AccountVault[2] memory vaults_) {
        t = t_;
        pool_ = t_.pool();
        pm_ = t_.pm();
        wmon_ = t_.wmon();
        usdc_ = t_.usdc();
        owners = owners_;
        keys = keys_;
        vaults = vaults_;
    }

    function _check(uint256 a) internal {
        ChogCreditPool.AccountData memory d = pool_.accountData(keys[a]);
        if (d.priceOk && d.debt > d.borrowPower) ghostViolation = true;
    }

    function positionCount() external view returns (uint256) {
        return allPositions.length;
    }

    function depositNewPosition(uint256 a, uint256 liq) external {
        a %= 2;
        liq = bound(liq, 1e9, uint256(t.L_2K()) * 20);
        MockPositionManager pm = pm_;
        uint256 id = pm.mint(owners[a], address(t.lpPool()), -887_220, 887_220, uint128(liq));
        vm.startPrank(owners[a]);
        pm.approve(address(vaults[a]), id);
        try vaults[a].depositPosition(id) {
            okDeposits++;
            allPositions.push(id);
            lastHolder[id] = owners[a]; // a deposit only adds power, so it is not checked
        } catch {}
        vm.stopPrank();
    }

    function withdrawPosition(uint256 a, uint256 i) external {
        a %= 2;
        uint256 n = vaults[a].positionCount();
        if (n == 0) return;
        uint256 id = vaults[a].positionAt(i % n);
        vm.prank(owners[a]);
        try vaults[a].withdrawPosition(id, owners[a]) {
            okWithdraws++;
            _check(a);
        } catch {}
    }

    function depositWmon(uint256 a, uint256 amt) external {
        a %= 2;
        amt = bound(amt, 1, 1_000e18);
        wmon_.mint(owners[a], amt);
        vm.startPrank(owners[a]);
        wmon_.approve(address(vaults[a]), amt);
        try vaults[a].depositERC20(address(wmon_), amt) {} catch {}
        vm.stopPrank();
    }

    function withdrawWmon(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 have = vaults[a].accounted(address(wmon_));
        if (have == 0) return;
        amt = bound(amt, 1, have);
        vm.prank(owners[a]);
        try vaults[a].withdrawERC20(address(wmon_), amt, owners[a]) {
            _check(a);
        } catch {}
    }

    function borrow(uint256 a, uint256 amt) external {
        a %= 2;
        ChogCreditPool.AccountData memory d = pool_.accountData(keys[a]);
        if (!d.priceOk || d.availableToBorrow == 0) return;
        amt = amt % 2 == 0 ? d.availableToBorrow : bound(amt, 1, d.availableToBorrow);
        vm.prank(owners[a]);
        try pool_.borrow(keys[a], amt) {
            okBorrows++;
            _check(a);
        } catch {}
    }

    function repay(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 debt = pool_.debtOf(keys[a]);
        if (debt == 0) return;
        amt = bound(amt, 1, debt);
        deal(address(usdc_), owners[a], usdc_.balanceOf(owners[a]) + amt);
        vm.startPrank(owners[a]);
        usdc_.approve(address(pool_), amt);
        try pool_.repay(keys[a], amt) {} catch {}
        vm.stopPrank();
    }

    /// @dev Prices move over a wide range; most of the time the pool follows, sometimes it lags by up to ~4%.
    function movePrice(uint256 price, uint256 lag) external {
        price = bound(price, 2e5, 6e6);
        MockOracle o = t.oracle();
        vm.prank(address(t)); // the oracle's owner is the test contract
        o.setPrice(address(wmon_), price);
        t.syncPoolPrice();
        lag = lag % 10;
        if (lag < 3) {
            uint160 s = t.lpPool().sqrtPriceX96();
            t.lpPool().setSqrtPrice(uint160(uint256(s) * (10_000 + lag * 100) / 10_000));
        }
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 20 days));
    }

    function liquidate(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 debt = pool_.debtOf(keys[a]);
        if (debt == 0) return;
        amt = bound(amt, 1, debt);
        address liq = address(0x11C);
        deal(address(usdc_), liq, 1e12);
        uint256 positionsBefore = vaults[a].positionCount();
        vm.startPrank(liq);
        usdc_.approve(address(pool_), type(uint256).max);
        try pool_.liquidate(keys[a], amt) returns (uint256 repaid) {
            okLiquidations++;
            if (positionsBefore != 0) okUnwinds++;
            repaid;
        } catch {}
        vm.stopPrank();
    }
}

contract LpInvariantTest is LpBase {
    LpHandler internal h;

    function setUp() public override {
        super.setUp();
        _supply(lender, 200_000 * USDC);
        _openAccount(alice, 1);
        _openAccount(bob, 5);
        address[2] memory owners = [alice, bob];
        bytes32[2] memory ks = [_key(1), _key(5)];
        AccountVault[2] memory vs =
            [AccountVault(registry.vaultOf(address(chog), 1)), AccountVault(registry.vaultOf(address(chog), 5))];
        h = new LpHandler(this, owners, ks, vs);
        targetContract(address(h));
        bytes4[] memory sels = new bytes4[](9);
        sels[0] = h.depositNewPosition.selector;
        sels[1] = h.withdrawPosition.selector;
        sels[2] = h.depositWmon.selector;
        sels[3] = h.withdrawWmon.selector;
        sels[4] = h.borrow.selector;
        sels[5] = h.repay.selector;
        sels[6] = h.movePrice.selector;
        sels[7] = h.warp.selector;
        sels[8] = h.liquidate.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
    }

    function invariant_noActionLeavesAnAccountOverItsBorrowingPower() external view {
        assertFalse(h.ghostViolation());
    }

    function invariant_aChogWithAPositionStaysInEscrow() external view {
        for (uint256 i; i < 2; ++i) {
            AccountVault v = AccountVault(registry.vaultOf(address(chog), i == 0 ? 1 : 5));
            if (v.positionCount() != 0) {
                assertEq(chog.ownerOf(i == 0 ? 1 : 5), address(escrow), "escrowed while a position is held");
            }
        }
    }

    function invariant_everyPositionIsWhereTheVaultSaysItIs() external view {
        uint256 n = h.positionCount();
        for (uint256 i; i < n; ++i) {
            uint256 id = h.allPositions(i);
            address holder = h.lastHolder(id);
            AccountVault v0 = AccountVault(registry.vaultOf(address(chog), 1));
            AccountVault v1 = AccountVault(registry.vaultOf(address(chog), 5));
            bool inV0 = v0.holdsPosition(id);
            bool inV1 = v1.holdsPosition(id);
            assertFalse(inV0 && inV1, "never in two vaults");
            address owner_ = pm.ownerOf(id);
            if (inV0) assertEq(owner_, address(v0));
            else if (inV1) assertEq(owner_, address(v1));
            else assertEq(owner_, holder, "withdrawn positions went back to the account that deposited them");
        }
    }

    function invariant_positionCountMatchesTheLimit() external view {
        assertLe(AccountVault(registry.vaultOf(address(chog), 1)).positionCount(), 2);
        assertLe(AccountVault(registry.vaultOf(address(chog), 5)).positionCount(), 2);
    }

    function invariant_accountedTokensNeverExceedBalances() external view {
        for (uint256 i; i < 2; ++i) {
            AccountVault v = AccountVault(registry.vaultOf(address(chog), i == 0 ? 1 : 5));
            assertLe(v.accounted(address(wmon)), wmon.balanceOf(address(v)));
            assertLe(v.accounted(address(usdc)), usdc.balanceOf(address(v)));
        }
    }

    /// @dev The handler really reaches deposits, borrows and unwinding liquidations (it is not vacuous).
    function test_handlerPathsAreNotVacuous() external {
        h.depositNewPosition(0, uint256(L_2K) * 10);
        h.borrow(0, 0);
        assertGt(h.okDeposits(), 0);
        assertGt(h.okBorrows(), 0);
        h.movePrice(4e5, 9); // WMON falls to 0.40, pool follows
        h.liquidate(0, 1e12);
        assertGt(h.okLiquidations(), 0);
        assertGt(h.okUnwinds(), 0);
        h.withdrawPosition(0, 0);
        assertFalse(h.ghostViolation());
    }
}
