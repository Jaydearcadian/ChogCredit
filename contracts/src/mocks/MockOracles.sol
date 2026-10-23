// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle, IAggregatorV3} from "../credit/interfaces/IPriceOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice TEST / TESTNET ONLY. Owner-set prices, no freshness. Never use with real funds: this is the "admin-set
///         price" the risk register forbids. Deployments using it must be labelled mock.
contract MockOracle is IPriceOracle {
    address public owner;
    mapping(address => uint256) public pricePerWholeToken; // loan-token raw units per 1 whole token
    bool public down;

    constructor() {
        owner = msg.sender;
    }

    function setPrice(address token, uint256 priceRaw) external {
        require(msg.sender == owner, "owner");
        pricePerWholeToken[token] = priceRaw;
    }

    function setDown(bool d) external {
        require(msg.sender == owner, "owner");
        down = d;
    }

    function quote(address token, uint256 amount) external view returns (uint256) {
        require(!down, "oracle down");
        uint256 p = pricePerWholeToken[token];
        require(p != 0, "no price");
        return amount * p / (10 ** IERC20Metadata(token).decimals());
    }
}

/// @notice TEST ONLY. A Chainlink-style aggregator whose every field is settable.
contract MockAggregator is IAggregatorV3 {
    uint8 public immutable override decimals;
    int256 public answer;
    uint256 public updatedAt;
    bool public reverts;

    constructor(uint8 dec, int256 initial) {
        decimals = dec;
        answer = initial;
        updatedAt = block.timestamp;
    }

    function set(int256 a, uint256 ts) external {
        answer = a;
        updatedAt = ts;
    }

    function setReverts(bool r) external {
        reverts = r;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!reverts, "feed down");
        return (1, answer, updatedAt, updatedAt, 1);
    }
}
