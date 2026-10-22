// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IChogAccountRegistry, AccountInfo} from "./interfaces/IChogAccountRegistry.sol";

/// @title AccountVault
/// @notice Custody for one Chog account. EIP-1167 clone created by the registry. Holds allowlisted ERC-20s only.
///         There is no generic `call(target, data)`: the only external effects are token transfers.
/// @dev GATE B SCOPE. No debt module exists yet, so withdrawals are limited only by control. Gate D adds the
///      post-withdrawal solvency check. Control and "may this account hold assets" both come from the registry.
contract AccountVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IChogAccountRegistry public registry;
    bytes32 public key;
    uint256 public stateNonce;

    error AlreadyInitialized();
    error OnlyRegistry();
    error NotController();
    error AssetsNotAccepted();
    error TokenNotAllowed(address token);
    error ZeroAmount();
    error ZeroAddress();
    error BalanceDeltaMismatch(uint256 expected, uint256 received);

    event Deposited(address indexed token, address indexed from, uint256 amount, uint256 stateNonce);
    event Withdrawn(address indexed token, address indexed to, uint256 amount, uint256 stateNonce);

    constructor() {
        // Lock the implementation so nobody can initialise it and treat it as an account.
        key = bytes32(uint256(1));
    }

    function initialize(address registry_, bytes32 key_) external {
        if (address(registry) != address(0) || key != bytes32(0)) revert AlreadyInitialized();
        if (msg.sender != registry_) revert OnlyRegistry();
        registry = IChogAccountRegistry(registry_);
        key = key_;
    }

    modifier onlyController() {
        if (!registry.isController(key, msg.sender)) revert NotController();
        _;
    }

    function info() public view returns (AccountInfo memory) {
        return registry.accountInfo(key);
    }

    function balanceOfToken(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Pull `amount` of an allowlisted token from the controller. Measures the balance delta and rejects
    ///         fee-on-transfer or otherwise short deliveries.
    function depositERC20(address token, uint256 amount) external nonReentrant onlyController {
        if (amount == 0) revert ZeroAmount();
        if (!registry.canAcceptAssets(key)) revert AssetsNotAccepted();
        if (!registry.isTokenAllowed(token)) revert TokenNotAllowed(token);

        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - beforeBal;
        if (received != amount) revert BalanceDeltaMismatch(amount, received);

        unchecked {
            ++stateNonce;
        }
        emit Deposited(token, msg.sender, amount, stateNonce);
    }

    /// @notice Send tokens to `to`. Gate D adds the debt and health checks.
    function withdrawERC20(address token, uint256 amount, address to) external nonReentrant onlyController {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            ++stateNonce;
        }
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount, stateNonce);
    }
}
