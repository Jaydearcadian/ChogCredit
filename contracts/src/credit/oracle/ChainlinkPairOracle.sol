// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceOracle, IAggregatorV3} from "../interfaces/IPriceOracle.sol";

/// @title ChainlinkPairOracle
/// @notice Prices a collateral token in loan-token units from USD feeds: value = amount * USD(token) / USD(loanToken).
///         Using the loan token's own USD feed means a loan-token depeg is reflected in collateral values.
///         Each token has a primary feed and an optional secondary feed (for example Chainlink plus RedStone). When a
///         secondary exists the two must agree within `maxDeviationBps` and the LOWER price is used.
/// @dev No owner and no setters: feeds, ages and bounds are fixed at deployment. Every failure reverts, which the pool
///      reads as "price unavailable". `answeredInRound` is not checked (deprecated, and not meaningful on every feed
///      adapter); freshness is `updatedAt` against `maxAge`. Heartbeats and deviation thresholds of the real feeds must
///      be confirmed before choosing `maxAge`; they are NOT verified in this repository.
contract ChainlinkPairOracle is IPriceOracle {
    struct FeedConfig {
        address token;
        address primary;
        address secondary; // address(0) = none
        uint32 maxAge; // seconds
        uint16 maxDeviationBps; // used only when a secondary exists
    }

    struct Feed {
        IAggregatorV3 primary;
        IAggregatorV3 secondary;
        uint8 primaryDecimals;
        uint8 secondaryDecimals;
        uint32 maxAge;
        uint16 maxDeviationBps;
        uint8 tokenDecimals;
        bool configured;
    }

    address public immutable loanToken;
    uint8 public immutable loanDecimals;
    mapping(address => Feed) public feedOf;

    error ZeroAddress();
    error BadConfig();
    error UnknownToken(address token);
    error InvalidPrice(address feed);
    error StalePrice(address feed, uint256 updatedAt);
    error FeedDeviation(uint256 primary, uint256 secondary);

    /// @param configs must include the loan token itself (its USD feed) and every collateral token.
    constructor(address loanToken_, FeedConfig[] memory configs) {
        if (loanToken_ == address(0)) revert ZeroAddress();
        loanToken = loanToken_;
        loanDecimals = IERC20Metadata(loanToken_).decimals();
        bool sawLoan;
        for (uint256 i; i < configs.length; ++i) {
            FeedConfig memory c = configs[i];
            if (c.token == address(0) || c.primary == address(0)) revert ZeroAddress();
            if (feedOf[c.token].configured) revert BadConfig();
            if (c.maxAge == 0) revert BadConfig();
            if (c.secondary != address(0) && (c.maxDeviationBps == 0 || c.maxDeviationBps > 2_000)) revert BadConfig();
            uint8 pd = IAggregatorV3(c.primary).decimals();
            uint8 sd = c.secondary == address(0) ? 0 : IAggregatorV3(c.secondary).decimals();
            if (pd > 18 || sd > 18) revert BadConfig();
            uint8 td = IERC20Metadata(c.token).decimals();
            if (td > 36) revert BadConfig();
            feedOf[c.token] = Feed(
                IAggregatorV3(c.primary), IAggregatorV3(c.secondary), pd, sd, c.maxAge, c.maxDeviationBps, td, true
            );
            if (c.token == loanToken_) sawLoan = true;
        }
        if (!sawLoan) revert BadConfig();
    }

    function quote(address token, uint256 amount) external view returns (uint256) {
        if (amount == 0) return 0;
        Feed storage tf = feedOf[token];
        if (!tf.configured) revert UnknownToken(token);
        uint256 pToken = _usd18(token);
        uint256 pLoan = _usd18(loanToken);
        // amount * (pToken / pLoan) * 10^loanDecimals / 10^tokenDecimals, one rounding step, rounded down.
        return Math.mulDiv(amount, pToken * (10 ** loanDecimals), pLoan * (10 ** tf.tokenDecimals));
    }

    function _usd18(address token) internal view returns (uint256) {
        Feed storage f = feedOf[token];
        if (!f.configured) revert UnknownToken(token);
        uint256 p1 = _read(f.primary, f.primaryDecimals, f.maxAge);
        if (address(f.secondary) == address(0)) return p1;
        uint256 p2 = _read(f.secondary, f.secondaryDecimals, f.maxAge);
        uint256 lo = p1 < p2 ? p1 : p2;
        uint256 hi = p1 < p2 ? p2 : p1;
        if ((hi - lo) * 10_000 > lo * f.maxDeviationBps) revert FeedDeviation(p1, p2);
        return lo; // conservative: the lower price
    }

    function _read(IAggregatorV3 feed, uint8 dec, uint32 maxAge) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice(address(feed));
        if (updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxAge) {
            revert StalePrice(address(feed), updatedAt);
        }
        return uint256(answer) * (10 ** (18 - dec));
    }
}
