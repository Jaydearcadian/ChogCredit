// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title LpMath
/// @notice Pure maths for valuing a Uniswap V3 style position at an externally supplied price. Written for this
///         repository from the published formulas (price = 1.0001^tick, Q64.96 square-root prices); it does not copy
///         Uniswap's GPL-licensed libraries. The constants below were generated with 120-digit decimal arithmetic.
/// @dev Amounts always round DOWN, the conservative direction for collateral.
library LpMath {
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    int24 internal constant MAX_TICK = 887272;
    uint256 internal constant Q96 = 1 << 96;

    error TickOutOfRange(int24 tick);
    error PriceOutOfRange();

    /// @notice sqrt(1.0001^tick) as a Q64.96 number.
    function sqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick));
        if (absTick > uint256(uint24(MAX_TICK))) revert TickOutOfRange(tick);

        // ratio = 1 / sqrt(1.0001^absTick) in Q128, built from the bits of absTick.
        uint256 ratio = 1 << 128;
        if ((absTick & 1) != 0) ratio = (ratio * 0xfffcb933bd6fad37aa2d162d1a594001) >> 128;
        if ((absTick & 2) != 0) ratio = (ratio * 0xfff97272373d413259a46990580e2139) >> 128;
        if ((absTick & 4) != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcb) >> 128;
        if ((absTick & 8) != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941ccf) >> 128;
        if ((absTick & 16) != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926643) >> 128;
        if ((absTick & 32) != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254bf) >> 128;
        if ((absTick & 64) != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52860) >> 128;
        if ((absTick & 128) != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3052) >> 128;
        if ((absTick & 256) != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a3) >> 128;
        if ((absTick & 512) != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e53) >> 128;
        if ((absTick & 1024) != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f2) >> 128;
        if ((absTick & 2048) != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d8) >> 128;
        if ((absTick & 4096) != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if ((absTick & 8192) != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e4) >> 128;
        if ((absTick & 16384) != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f6) >> 128;
        if ((absTick & 32768) != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa5) >> 128;
        if ((absTick & 65536) != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc8) >> 128;
        if ((absTick & 131072) != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if ((absTick & 262144) != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe97) >> 128;
        if ((absTick & 524288) != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;
        if (tick > 0) ratio = type(uint256).max / ratio;
        // Q128 -> Q96, rounding up
        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @notice Token amounts held by `liquidity` between two tick prices when the current price is `sqrtP`.
    function amountsForLiquidity(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            amount0 = _amount0(sqrtA, sqrtB, liquidity);
        } else if (sqrtP < sqrtB) {
            amount0 = _amount0(sqrtP, sqrtB, liquidity);
            amount1 = Math.mulDiv(liquidity, sqrtP - sqrtA, Q96);
        } else {
            amount1 = Math.mulDiv(liquidity, sqrtB - sqrtA, Q96);
        }
    }

    function _amount0(uint160 lo, uint160 hi, uint128 liquidity) private pure returns (uint256) {
        // floor(floor(L * 2^96 * (hi - lo) / hi) / lo) == floor(L * 2^96 * (hi - lo) / (hi * lo))
        return Math.mulDiv(Math.mulDiv(uint256(liquidity) << 96, hi - lo, hi), 1, lo);
    }

    /// @notice Q64.96 square-root price of token0 in token1 raw units, from two oracle values.
    /// @param value0 loan-token value of `scale0` raw units of token0
    /// @param value1 loan-token value of `scale1` raw units of token1
    /// @dev raw price = (value0 / scale0) / (value1 / scale1); sqrtPriceX96 = sqrt(raw price) * 2^96.
    function sqrtPriceFromValues(uint256 value0, uint256 scale0, uint256 value1, uint256 scale1)
        internal
        pure
        returns (uint160 s)
    {
        bool ok;
        (ok, s) = trySqrtPriceFromValues(value0, scale0, value1, scale1);
        if (!ok) revert PriceOutOfRange();
    }

    /// @dev Same, but reports failure instead of reverting. Intermediate overflow is checked, so an extreme price
    ///      comes back as `ok == false`.
    function trySqrtPriceFromValues(uint256 value0, uint256 scale0, uint256 value1, uint256 scale1)
        internal
        pure
        returns (bool ok, uint160 s)
    {
        if (value0 == 0 || value1 == 0 || scale0 == 0 || scale1 == 0) return (false, 0);
        (bool ok1, uint256 q) = _tryMulDiv(value0, scale1, value1);
        if (!ok1) return (false, 0);
        (bool ok2, uint256 ratioX192) = _tryMulDiv(q, uint256(1) << 192, scale0);
        if (!ok2) return (false, 0);
        uint256 r = Math.sqrt(ratioX192);
        if (r < MIN_SQRT_RATIO || r > MAX_SQRT_RATIO) return (false, 0);
        return (true, uint160(r));
    }

    function _tryMulDiv(uint256 x, uint256 y, uint256 d) private pure returns (bool, uint256) {
        // full-precision product must fit once divided; Math.tryMul-style guard on the high word
        uint256 hi;
        uint256 lo;
        assembly {
            let mm := mulmod(x, y, not(0))
            lo := mul(x, y)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
        if (hi >= d) return (false, 0);
        return (true, Math.mulDiv(x, y, d));
    }

    /// @notice Price deviation between two square-root prices, in basis points of price (not of the square root).
    function deviationBps(uint160 a, uint160 b) internal pure returns (uint256) {
        (uint256 lo, uint256 hi) = a < b ? (uint256(a), uint256(b)) : (uint256(b), uint256(a));
        uint256 t = Math.mulDiv(hi, 1e8, lo); // sqrt ratio, 8 decimals
        uint256 priceRatio = (t * t) / 1e8; // price ratio, 8 decimals, rounded down
        return (priceRatio - 1e8) / 1e4;
    }
}
