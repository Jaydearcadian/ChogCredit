// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IChogAccountRegistry, IChogCreditEscrow, ReleaseBlocker} from "./interfaces/IChogAccountRegistry.sol";

/// @title ChogCreditEscrow
/// @notice Holds the original Chog NFT while its account carries assets, positions or debt, and records the
///         beneficial owner. `ownerOf(tokenId)` on the collection is this contract while escrowed; the beneficial
///         owner is recorded here.
/// @dev Trust boundary. There is no owner, admin, pause or rescue function. The only way out is `release`, callable
///      by the beneficial owner when the account is empty and clear of liabilities. Deposit is by
///      `safeTransferFrom` into `onERC721Received`: NFTs sent with plain `transferFrom`, or from collections that
///      are not on the registry allowlist, are NOT recorded and cannot be recovered. The UI must only use
///      `safeTransferFrom`. Created by the registry in its constructor.
contract ChogCreditEscrow is IChogCreditEscrow, IERC721Receiver, ReentrancyGuard {
    IChogAccountRegistry public immutable registry;
    mapping(bytes32 => address) private _beneficial;

    error NotRegistry();
    error CollectionNotAllowed(address collection);
    error AccountNotOpen(bytes32 key);
    error AlreadyEscrowed(bytes32 key);
    error NotHeld(address collection, uint256 tokenId);
    error ZeroAddress();
    error NotEscrowed(bytes32 key);
    error NotBeneficialOwner(bytes32 key, address caller);
    error ReleaseBlocked(bytes32 key, ReleaseBlocker reason);

    event Escrowed(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address beneficialOwner);
    event Released(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address to);

    constructor(address registry_) {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = IChogAccountRegistry(registry_);
    }

    function beneficialOwnerOf(bytes32 key) external view returns (address) {
        return _beneficial[key];
    }

    function isEscrowed(bytes32 key) external view returns (bool) {
        return _beneficial[key] != address(0);
    }

    /// @notice Entry point. `msg.sender` is the collection; `from` is the previous owner and becomes the beneficial
    ///         owner. The account must already exist (open it first with `registry.createAccount`).
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        nonReentrant
        returns (bytes4)
    {
        address collection = msg.sender;
        if (!registry.isCollectionAllowed(collection)) revert CollectionNotAllowed(collection);
        if (from == address(0)) revert ZeroAddress();
        bytes32 key = registry.accountKey(collection, tokenId);
        if (!registry.accountExists(key)) revert AccountNotOpen(key);
        if (_beneficial[key] != address(0)) revert AlreadyEscrowed(key);
        // Do not trust the callback alone: the token must really be here now.
        if (IERC721(collection).ownerOf(tokenId) != address(this)) revert NotHeld(collection, tokenId);

        _beneficial[key] = from;
        emit Escrowed(key, collection, tokenId, from);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Return the Chog to `to`. Only the beneficial owner, and only when the registry reports no blocker.
    ///         Sending to a contract that cannot hold ERC-721s strands the token; check `to` first.
    function release(address collection, uint256 tokenId, address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        bytes32 key = registry.accountKey(collection, tokenId);
        address beneficial = _beneficial[key];
        if (beneficial == address(0)) revert NotEscrowed(key);
        if (msg.sender != beneficial) revert NotBeneficialOwner(key, msg.sender);
        ReleaseBlocker blocker = registry.releaseBlocker(key);
        if (blocker != ReleaseBlocker.None) revert ReleaseBlocked(key, blocker);

        delete _beneficial[key]; // effects before the external transfer
        emit Released(key, collection, tokenId, to);
        // transferFrom, not safeTransferFrom: no callback into `to`. EIP-7702-delegated EOAs (common Chog holders)
        // may run a delegate that lacks the ERC-721 receiver hook, and marketplaces such as Seaport also use
        // transferFrom. The beneficial owner chooses `to` and bears the risk of a non-receiving contract.
        IERC721(collection).transferFrom(address(this), to, tokenId);
    }
}
