// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditBase} from "./CreditBase.sol";
import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {MockUSDC} from "../../src/mocks/MockTokens.sol";
import {MockOracle} from "../../src/mocks/MockOracles.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

/// @dev Random interleavings of lending, borrowing, repaying, collateral moves, price swings, time and liquidation.
///      Reverting calls are skipped. Ghost variables record what the protocol must preserve.
contract PoolHandler is Test {
    ChogCreditPool public pool;
    ChogAccountRegistry public registry;
    MockUSDC public usdc;
    TestToken public wmon;
    MockOracle public oracle;
    address public oracleOwner;

    address[2] public lenders = [address(0x1E4D3), address(0x1E4D4)];
    address[2] public borrowers = [address(0xA11CE), address(0xB0B)];
    bytes32[2] public keys;
    AccountVault[2] public vaults;
    address public liquidator = address(0x11C);

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    uint256 public ghostSeized;
    uint256 public ghostWriteOffs;
    uint256 public ghostLastIndex;
    uint256 public ghostPpsMax;
    bool public ghostViolation;
    uint256 public okBorrows;
    uint256 public okLiquidations;
    uint256 public okRepays;

    constructor(
        ChogCreditPool p,
        ChogAccountRegistry r,
        MockUSDC u,
        TestToken w,
        MockOracle o,
        address oracleOwner_,
        bytes32[2] memory ks
    ) {
        pool = p;
        registry = r;
        usdc = u;
        wmon = w;
        oracle = o;
        oracleOwner = oracleOwner_;
        keys = ks;
        for (uint256 i; i < 2; i++) {
            vaults[i] = AccountVault(r.accountInfo(ks[i]).vault);
        }
        ghostLastIndex = p.borrowIndex();
        ghostPpsMax = p.convertToAssets(1e12);
    }

    function _sync() internal {
        uint256 idx = pool.borrowIndex();
        if (idx > ghostLastIndex) ghostLastIndex = idx;
        uint256 pps = pool.convertToAssets(1e12);
        if (pps > ghostPpsMax) ghostPpsMax = pps;
    }

    function _checkPower(uint256 a) internal {
        ChogCreditPool.AccountData memory d = pool.accountData(keys[a]);
        if (d.priceOk && d.debt > d.borrowPower) ghostViolation = true;
    }

    function supply(uint256 l, uint256 amt) external {
        address who = lenders[l % 2];
        amt = bound(amt, 1, 50_000e6);
        deal(address(usdc), who, usdc.balanceOf(who) + amt);
        vm.startPrank(who);
        usdc.approve(address(pool), amt);
        try pool.supply(amt) {} catch {}
        vm.stopPrank();
        _sync();
    }

    function redeem(uint256 l, uint256 frac) external {
        address who = lenders[l % 2];
        uint256 s = pool.maxRedeem(who);
        if (s == 0) return;
        s = bound(frac, 1, s);
        vm.prank(who);
        try pool.redeem(s) {} catch {}
        _sync();
    }

    function depositCollateral(uint256 a, uint256 amt) external {
        a %= 2;
        amt = bound(amt, 1, 2_000e18);
        wmon.mint(borrowers[a], amt);
        vm.startPrank(borrowers[a]);
        wmon.approve(address(vaults[a]), amt);
        try vaults[a].depositERC20(address(wmon), amt) {
            ghostDeposited += amt;
        } catch {}
        vm.stopPrank();
        _sync();
    }

    function withdrawCollateral(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 have = vaults[a].accounted(address(wmon));
        if (have == 0) return;
        amt = bound(amt, 1, have);
        vm.prank(borrowers[a]);
        try vaults[a].withdrawERC20(address(wmon), amt, borrowers[a]) {
            ghostWithdrawn += amt;
            _checkPower(a);
        } catch {}
        _sync();
    }

    /// @dev Sized from the account's real headroom so that accounts regularly end up at or near their limit.
    function borrow(uint256 a, uint256 amt) external {
        a %= 2;
        ChogCreditPool.AccountData memory d = pool.accountData(keys[a]);
        if (!d.priceOk || d.availableToBorrow == 0) return;
        uint256 naive = d.borrowPower > d.debt ? d.borrowPower - d.debt : 0; // may overshoot by 1 unit: must be refused
        amt =
            amt % 3 == 0 ? d.availableToBorrow : amt % 3 == 1 && naive > 0 ? naive : bound(amt, 1, d.availableToBorrow);
        vm.prank(borrowers[a]);
        try pool.borrow(keys[a], amt) {
            okBorrows++;
            _checkPower(a);
        } catch {}
        _sync();
    }

    function repay(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 debt = pool.debtOf(keys[a]);
        if (debt == 0) return;
        amt = bound(amt, 1, debt);
        deal(address(usdc), borrowers[a], usdc.balanceOf(borrowers[a]) + amt);
        vm.startPrank(borrowers[a]);
        usdc.approve(address(pool), amt);
        try pool.repay(keys[a], amt) {
            okRepays++;
        } catch {}
        vm.stopPrank();
        _sync();
    }

    function movePrice(uint256 p) external {
        p = bound(p, 300_000, 4_000_000);
        vm.prank(oracleOwner);
        oracle.setPrice(address(wmon), p);
        _sync();
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 30 days));
        _sync();
    }

    function liquidate(uint256 a, uint256 amt) external {
        a %= 2;
        uint256 debt = pool.debtOf(keys[a]);
        if (debt == 0) return;
        amt = bound(amt, 1, debt);
        deal(address(usdc), liquidator, usdc.balanceOf(liquidator) + amt);
        uint256 debtBefore = pool.debtOf(keys[a]);
        uint256 wmonBefore = wmon.balanceOf(liquidator);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), amt);
        try pool.liquidate(keys[a], amt) returns (uint256 repaid) {
            okLiquidations++;
            ghostSeized += wmon.balanceOf(liquidator) - wmonBefore;
            if (pool.debtOf(keys[a]) == 0 && debtBefore > repaid) ghostWriteOffs++;
        } catch {}
        vm.stopPrank();
        _sync();
    }
}

contract PoolInvariantTest is CreditBase {
    PoolHandler internal h;

    function setUp() public override {
        super.setUp();
        ChogCreditPool.PoolConfig memory pc = _poolConfig();
        pc.supplyCap = type(uint128).max;
        pc.borrowCap = type(uint128).max;
        pc.accountDebtCap = type(uint128).max;
        _deploy(pc, _collaterals(false));
        // fund two escrowed accounts (Chogs 1 and 5) with a little collateral so they exist
        _fund(alice, 1, 10 * WMON);
        _fund(bob, 5, 10 * WMON);
        bytes32[2] memory ks = [_key(1), _key(5)];
        h = new PoolHandler(pool, registry, usdc, wmon, oracle, address(this), ks);
        // the handler's borrowers are the same addresses as alice and bob
        targetContract(address(h));
        // the initial 10 WMON deposits came from the fixture, count them as deposited
    }

    function invariant_debtAccountingMatches() external view {
        assertEq(pool.totalScaledDebt(), pool.debtScaled(h.keys(0)) + pool.debtScaled(h.keys(1)), "scaled debt drift");
    }

    function invariant_sharesAccountingMatches() external view {
        assertEq(pool.totalShares(), pool.sharesOf(h.lenders(0)) + pool.sharesOf(h.lenders(1)), "share drift");
    }

    function invariant_lenderClaimsNeverExceedAssets() external view {
        uint256 claims =
            pool.convertToAssets(pool.sharesOf(h.lenders(0))) + pool.convertToAssets(pool.sharesOf(h.lenders(1)));
        assertLe(claims, pool.totalAssets(), "lenders are owed more than the pool has");
    }

    function invariant_borrowIndexNeverFalls() external view {
        assertGe(pool.borrowIndex(), h.ghostLastIndex());
        assertGe(pool.borrowIndex(), pool.RAY());
    }

    function invariant_noActionLeftAnAccountOverItsBorrowingPower() external view {
        assertFalse(h.ghostViolation(), "a borrow or withdrawal left debt above borrowing power");
    }

    function invariant_collateralIsConserved() external view {
        uint256 inVaults = h.vaults(0).accounted(address(wmon)) + h.vaults(1).accounted(address(wmon));
        // the two fixture deposits of 10 WMON each are not in the ghost counters
        assertEq(
            inVaults + h.ghostWithdrawn() + h.ghostSeized(),
            h.ghostDeposited() + 20 * WMON,
            "collateral leaked or minted"
        );
        assertEq(
            wmon.balanceOf(address(h.vaults(0))) + wmon.balanceOf(address(h.vaults(1))),
            inVaults,
            "vault balance != accounted"
        );
    }

    function invariant_sharePriceOnlyFallsThroughBadDebt() external view {
        if (h.ghostWriteOffs() == 0) {
            assertGe(pool.convertToAssets(1e12), h.ghostPpsMax(), "share price fell without a write-off");
        }
    }

    function invariant_poolCashPlusDebtEqualsAssets() external view {
        assertEq(pool.totalAssets(), usdc.balanceOf(address(pool)) + pool.totalDebt());
    }

    /// @dev Non-vacuity: the handler's borrow, repay and liquidation paths really execute in a scripted run.
    function test_handlerPathsAreNotVacuous() external {
        h.supply(0, 20_000e6);
        h.depositCollateral(0, 1_000e18);
        h.borrow(0, 500e6);
        assertEq(h.okBorrows(), 1);
        h.repay(0, 100e6);
        assertEq(h.okRepays(), 1);
        h.movePrice(300_000); // WMON crashes to $0.30
        h.liquidate(0, 400e6);
        assertEq(h.okLiquidations(), 1, "liquidation did not execute");
        assertGt(wmon.balanceOf(h.liquidator()), 0);
        h.warp(10 days);
        assertFalse(h.ghostViolation());
    }
}
