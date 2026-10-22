// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IChogAccountRegistry, AccountInfo} from "./interfaces/IChogAccountRegistry.sol";

/// @title AccountVault
/// @notice Custody for one Chog account. EIP-1167 clone created by the registry. Holds allowlisted ERC-20s only.
///         There is no generic `call(target, data)`: the only external effects are token transfers.
/// @dev GATE C. Balances are tracked per token (`accounted`), not read from `balanceOf`, so an unsolicited transfer
///      cannot make the account look non-empty and block release of the Chog. Control, "may this account hold
///      assets" and debt all come from the registry. Withdrawals ask the credit module whether the account
///      stays within its borrowing limit.
contract AccountVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IChogAccountRegistry public registry;
    bytes32 public key;
    uint256 public stateNonce;
    mapping(address => uint256) public accounted;
    uint256 public nonEmptyTokens;

    error AlreadyInitialized();
    error OnlyRegistry();
    error NotController();
    error AssetsNotAccepted();
    error TokenNotAllowed(address token);
    error ZeroAmount();
    error ZeroAddress();
    error BalanceDeltaMismatch(uint256 expected, uint256 received);
    error WithdrawalBlocked();
    error OnlyCreditModule();
    error ExceedsAccounted(uint256 requested, uint256 accounted);
    error NothingToSweep();

    event Deposited(address indexed token, address indexed from, uint256 amount, uint256 stateNonce);
    event Withdrawn(address indexed token, address indexed to, uint256 amount, uint256 stateNonce);
    event Seized(address indexed token, address indexed to, uint256 amount, uint256 stateNonce);

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

        if (accounted[token] == 0) ++nonEmptyTokens;
        accounted[token] += amount;
        unchecked {
            ++stateNonce;
        }
        emit Deposited(token, msg.sender, amount, stateNonce);
    }

    /// @notice True when no accounted token balance remains. Unsolicited transfers do not count.
    function isEmpty() external view returns (bool) {
        return nonEmptyTokens == 0;
    }

    /// @notice Send accounted tokens to `to`, unless the credit module says the account would end up over its
    ///         borrowing limit.
    function withdrawERC20(address token, uint256 amount, address to) external nonReentrant onlyController {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        uint256 have = accounted[token];
        if (amount > have) revert ExceedsAccounted(amount, have);
        // With no debt this needs no price; with debt the credit module checks the post-withdrawal borrowing limit.
        // A module that fails or refuses blocks the withdrawal (fail closed).
        if (!registry.withdrawAllowed(key, token, amount)) revert WithdrawalBlocked();
        unchecked {
            accounted[token] = have - amount;
            ++stateNonce;
        }
        if (have == amount) --nonEmptyTokens;
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount, stateNonce);
    }

    /// @notice Liquidation path: the bound credit module moves accounted collateral to a liquidator. It is the only
    ///         way assets leave a vault other than the controller's own withdrawal.
    function seizeCollateral(address token, uint256 amount, address to) external nonReentrant {
        if (msg.sender != registry.creditModule()) revert OnlyCreditModule();
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        uint256 have = accounted[token];
        if (amount > have) revert ExceedsAccounted(amount, have);
        unchecked {
            accounted[token] = have - amount;
            ++stateNonce;
        }
        if (have == amount) --nonEmptyTokens;
        IERC20(token).safeTransfer(to, amount);
        emit Seized(token, to, amount, stateNonce);
    }

    /// @notice Recover tokens sent here without a deposit (anything above the accounted balance).
    function sweepUnaccounted(address token, address to) external nonReentrant onlyController {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 have = accounted[token];
        if (bal <= have) revert NothingToSweep();
        // A sweep changes what a buyer could see in the vault, so it must void signed acceptances too.
        unchecked {
            ++stateNonce;
        }
        IERC20(token).safeTransfer(to, bal - have);
    }
}
