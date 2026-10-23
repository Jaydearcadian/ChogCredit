// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Values collateral in units of the pool's loan token (for example USDC raw units).
interface IPriceOracle {
    /// @notice Value of `amount` raw units of `token`, in raw units of the loan token, rounded DOWN.
    /// @dev MUST revert if the price is missing, stale, non-positive, or sources disagree. The pool treats a revert as
    ///      "price unavailable" and fails closed for anything that increases risk.
    function quote(address token, uint256 amount) external view returns (uint256);
}

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
