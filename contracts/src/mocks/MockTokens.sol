// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TESTNET/LOCAL ONLY token. Open faucet. Never deploy or use as real USDC.
contract MockUSDC is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 10_000 * 1e6;
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}

/// @notice TESTNET/LOCAL ONLY collateral token with an open faucet.
contract MockCollateral is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1_000 ether;
    constructor() ERC20("Mock Chog Collateral", "mCHOGC") {}

    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
