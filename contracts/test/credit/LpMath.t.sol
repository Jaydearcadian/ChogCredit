// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LpMath} from "../../src/credit/lib/LpMath.sol";

contract LpMathHarness {
    function sqrtAt(int24 t) external pure returns (uint160) {
        return LpMath.sqrtRatioAtTick(t);
    }

    function fromValues(uint256 a, uint256 b, uint256 c, uint256 d) external pure returns (uint160) {
        return LpMath.sqrtPriceFromValues(a, b, c, d);
    }
}

contract LpMathTest is Test {
    LpMathHarness internal h = new LpMathHarness();

    /// @dev `expected` is floor(2^96 * 1.0001^(tick/2)) computed with 120-digit decimals outside Solidity. The
    ///      library rounds up and accumulates tiny steps, so allow one part in 1e15 plus a couple of units.
    function _check(int24 tick, uint256 expected) internal view {
        uint256 got = h.sqrtAt(tick);
        uint256 tol = expected / 1e15 + 2;
        assertApproxEqAbs(got, expected, tol, "sqrt ratio off the independent vector");
    }

    function test_sqrtRatio_matchesIndependentVectors() external view {
        _check(0, 79228162514264337593543950336);
        _check(1, 79232123823359799118286999567);
        _check(-1, 79224201403219477170569942573);
        _check(60, 79466191966197645195421774832);
        _check(-60, 78990846045029531151608375685);
        _check(1000, 83290069058676223003182343269);
        _check(-1000, 75364347830767020784054125654);
        _check(-314969, 11475103217426936530956);
        _check(-27053, 20486158252762647182257538428);
        _check(100000, 11755562826496067164730007768449);
        _check(-100000, 533968626430936354154228407);
        _check(887220, 1457652066949847389937902910258958406565750968362);
        _check(-887220, 4306310043);
        _check(887272, 1461446703485210103244672773810124308346321380902);
        _check(-887272, 4295128738);
        _check(500000, 5697689776495288729098254599936056708424);
        _check(-500000, 1101692437043807370);
    }

    function test_sqrtRatio_exactAtZero_andRangeEdges() external {
        assertEq(h.sqrtAt(0), 1 << 96);
        assertEq(h.sqrtAt(-887272), LpMath.MIN_SQRT_RATIO);
        assertLe(h.sqrtAt(887272), LpMath.MAX_SQRT_RATIO);
        vm.expectRevert(abi.encodeWithSelector(LpMath.TickOutOfRange.selector, int24(887273)));
        h.sqrtAt(887273);
        vm.expectRevert(abi.encodeWithSelector(LpMath.TickOutOfRange.selector, int24(-887273)));
        h.sqrtAt(-887273);
    }

    function testFuzz_sqrtRatio_isStrictlyIncreasing(int24 t) external view {
        t = int24(bound(int256(t), -887272, 887271));
        assertLt(h.sqrtAt(t), h.sqrtAt(t + 1));
    }

    function testFuzz_sqrtRatio_symmetry(int24 t) external view {
        t = int24(bound(int256(t), 1, 887272));
        // sqrt(p(t)) * sqrt(p(-t)) == 1 (in Q96 squared), within rounding
        uint256 prod = uint256(h.sqrtAt(t)) * uint256(h.sqrtAt(-t));
        uint256 one = uint256(1) << 192;
        uint256 tol = one / 1e9; // low ticks are coarse because the small side has few significant bits
        assertApproxEqAbs(prod, one, tol);
    }

    // ---------------------------------------------------------------- amounts

    function test_amounts_belowInAbove() external pure {
        uint160 a = LpMath.sqrtRatioAtTick(-600);
        uint160 b = LpMath.sqrtRatioAtTick(600);
        uint128 L = 1e18;
        (uint256 a0, uint256 a1) = LpMath.amountsForLiquidity(LpMath.sqrtRatioAtTick(-1200), a, b, L);
        assertGt(a0, 0);
        assertEq(a1, 0, "below range: all token0");
        (a0, a1) = LpMath.amountsForLiquidity(LpMath.sqrtRatioAtTick(1200), a, b, L);
        assertEq(a0, 0, "above range: all token1");
        assertGt(a1, 0);
        (a0, a1) = LpMath.amountsForLiquidity(LpMath.sqrtRatioAtTick(0), a, b, L);
        assertGt(a0, 0);
        assertGt(a1, 0);
    }

    function test_amounts_knownValue() external pure {
        // L = 1e18 over ticks [-600, 600] at price 1: amount0 = amount1 = L * (1 - 1.0001^-300 ...) ~ 0.029554e18
        uint160 a = LpMath.sqrtRatioAtTick(-600);
        uint160 b = LpMath.sqrtRatioAtTick(600);
        (uint256 a0, uint256 a1) = LpMath.amountsForLiquidity(uint160(1 << 96), a, b, 1e18);
        assertApproxEqRel(a0, 29_553_010_879_137_169, 1e-9 ether);
        assertApproxEqRel(a1, 29_553_010_879_137_169, 1e-9 ether);
    }

    function testFuzz_amounts_valueIsContinuousAtTheEdges(uint128 L, int24 ta, int24 tb) external pure {
        L = uint128(bound(L, 1, type(uint96).max));
        ta = int24(bound(int256(ta), -800_000, 799_000));
        tb = int24(bound(int256(tb), int256(ta) + 60, 800_000));
        uint160 a = LpMath.sqrtRatioAtTick(ta);
        uint160 b = LpMath.sqrtRatioAtTick(tb);
        // at the lower edge the position is all token0; at the upper edge all token1; from inside it is neither more
        // token0 than at the lower edge nor more token1 than at the upper edge.
        (uint256 lo0, uint256 lo1) = LpMath.amountsForLiquidity(a, a, b, L);
        (uint256 hi0, uint256 hi1) = LpMath.amountsForLiquidity(b, a, b, L);
        assertEq(lo1, 0);
        assertEq(hi0, 0);
        uint160 mid = uint160((uint256(a) + uint256(b)) / 2);
        (uint256 m0, uint256 m1) = LpMath.amountsForLiquidity(mid, a, b, L);
        assertLe(m0, lo0);
        assertLe(m1, hi1);
    }

    function testFuzz_amounts_scaleLinearlyWithLiquidity(uint64 L) external pure {
        L = uint64(bound(L, 1, type(uint64).max / 2));
        uint160 a = LpMath.sqrtRatioAtTick(-3000);
        uint160 b = LpMath.sqrtRatioAtTick(9000);
        uint160 p = LpMath.sqrtRatioAtTick(100);
        (uint256 x0, uint256 x1) = LpMath.amountsForLiquidity(p, a, b, L);
        (uint256 y0, uint256 y1) = LpMath.amountsForLiquidity(p, a, b, uint128(L) * 2);
        // doubling L at most doubles each amount (rounding down), and loses less than 2 units
        assertLe(y0, 2 * x0 + 1);
        assertGe(y0 + 2, 2 * x0);
        assertLe(y1, 2 * x1 + 1);
        assertGe(y1 + 2, 2 * x1);
    }

    function test_amounts_swappedBoundsAreAccepted() external pure {
        uint160 a = LpMath.sqrtRatioAtTick(-600);
        uint160 b = LpMath.sqrtRatioAtTick(600);
        (uint256 x0, uint256 x1) = LpMath.amountsForLiquidity(uint160(1 << 96), a, b, 1e18);
        (uint256 y0, uint256 y1) = LpMath.amountsForLiquidity(uint160(1 << 96), b, a, 1e18);
        assertEq(x0, y0);
        assertEq(x1, y1);
    }

    // ---------------------------------------------------------------- oracle price -> sqrt price

    function test_sqrtPriceFromValues_wmonUsdc() external view {
        // WMON (18 dec) is token0, USDC (6 dec) token1. 1e6 whole WMON is worth 21,000 USDC => 21_000e6 raw.
        // raw price = (21_000e6 / 1e24) / (1e6 / 1e6) = 2.1e-14 => sqrt = 1.4491e-7 => x 2^96
        uint160 s = h.fromValues(21_000e6, 1e24, 1e6, 1e6);
        uint256 expected = 11_480_726_233_346_480_000_000; // sqrt(2.1e-14) * 2^96 (approx, see tolerance)
        assertApproxEqRel(uint256(s), expected, 1e-3 ether);
    }

    function test_sqrtPriceFromValues_roundTripsThroughTicks() external view {
        // token0 = 1 whole (1e18 raw) worth 2e6, token1 = 1 whole (1e18 raw) worth 1e6 => raw price 2
        uint160 s = h.fromValues(2e6, 1e18, 1e6, 1e18);
        // price 2 => tick = ln(2)/ln(1.0001) = 6931.8; sqrt price between ticks 6931 and 6932 prices
        assertGe(s, h.sqrtAt(6930));
        assertLe(s, h.sqrtAt(6933));
    }

    function test_sqrtPriceFromValues_zeroOrExtremeReverts() external {
        vm.expectRevert(LpMath.PriceOutOfRange.selector);
        h.fromValues(0, 1e18, 1e6, 1e6);
        vm.expectRevert(LpMath.PriceOutOfRange.selector);
        h.fromValues(1e6, 1e18, 0, 1e6);
        vm.expectRevert(); // price far above the representable range: mulDiv overflow or range check
        h.fromValues(type(uint128).max, 1, 1, 1e18);
    }

    function test_deviationBps() external pure {
        uint160 p = uint160(1 << 96);
        assertEq(LpMath.deviationBps(p, p), 0);
        // a 1% price move is a ~0.4988% move in the square root
        uint160 q = uint160((uint256(p) * 1_004_988) / 1_000_000);
        uint256 d = LpMath.deviationBps(p, q);
        assertGe(d, 99);
        assertLe(d, 101);
        assertEq(LpMath.deviationBps(p, q), LpMath.deviationBps(q, p), "symmetric");
    }
}
