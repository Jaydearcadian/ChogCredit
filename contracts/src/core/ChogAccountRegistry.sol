// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IChogAccountRegistry, AccountInfo} from "./interfaces/IChogAccountRegistry.sol";
import {AccountVault} from "./AccountVault.sol";

/// @title ChogAccountRegistry
/// @notice Maps an existing Chog NFT (chainId, collection, tokenId) to exactly one portfolio vault.
///         It never mints an identity NFT. The collection and asset allowlists are fixed at deployment and have no
///         setter, so no EOA can widen them later.
/// @dev GATE B SCOPE. Control is derived from the collection's live `ownerOf`. That is only safe while the vault holds
///      nothing: a sale of the NFT would hand over the vault. `allowWalletHeldDeposits` is therefore false by
///      default; it exists only so Gate B plumbing can be tested. Gate C replaces it with NFT escrow
///      (`canAcceptAssets` becomes true only when the NFT is escrowed). Never deploy with it true outside local tests.
contract ChogAccountRegistry is IChogAccountRegistry {
    address public immutable vaultImplementation;
    bool public immutable allowWalletHeldDeposits;

    mapping(address => bool) public isCollectionAllowed;
    mapping(address => bool) public isTokenAllowed;
    mapping(bytes32 => AccountInfo) private _accounts;

    constructor(address[] memory collections, address[] memory tokens, bool walletHeldDeposits) {
        if (collections.length == 0) revert EmptyAllowlist();
        for (uint256 i; i < collections.length; ++i) {
            address c = collections[i];
            if (c == address(0)) revert ZeroAddress();
            if (isCollectionAllowed[c]) revert DuplicateEntry(c);
            isCollectionAllowed[c] = true;
        }
        for (uint256 i; i < tokens.length; ++i) {
            address t = tokens[i];
            if (t == address(0)) revert ZeroAddress();
            if (isTokenAllowed[t]) revert DuplicateEntry(t);
            isTokenAllowed[t] = true;
        }
        allowWalletHeldDeposits = walletHeldDeposits;
        vaultImplementation = address(new AccountVault());
    }

    // ---------------------------------------------------------------- views

    function accountKey(address collection, uint256 tokenId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, collection, tokenId));
    }

    function accountInfo(bytes32 key) external view returns (AccountInfo memory info) {
        info = _accounts[key];
        if (info.vault == address(0)) revert UnknownAccount(key);
    }

    function vaultOf(address collection, uint256 tokenId) external view returns (address) {
        return _accounts[accountKey(collection, tokenId)].vault;
    }

    function predictVault(address collection, uint256 tokenId) external view returns (address) {
        return Clones.predictDeterministicAddress(vaultImplementation, accountKey(collection, tokenId), address(this));
    }

    function isController(bytes32 key, address who) external view returns (bool) {
        AccountInfo storage info = _accounts[key];
        if (info.vault == address(0) || who == address(0)) return false;
        // Deliberately no `who.code.length` test: many Chog holders are EIP-7702-delegated EOAs and have code.
        try IERC721(info.collection).ownerOf(info.tokenId) returns (address holder) {
            return holder == who;
        } catch {
            return false;
        }
    }

    function canAcceptAssets(bytes32 key) external view returns (bool) {
        if (_accounts[key].vault == address(0)) return false;
        return allowWalletHeldDeposits; // Gate C: escrowed(key)
    }

    // ---------------------------------------------------------------- create

    /// @notice Open the account for a Chog you currently hold. One account per (chain, collection, tokenId).
    function createAccount(address collection, uint256 tokenId) external returns (address vault) {
        if (!isCollectionAllowed[collection]) revert CollectionNotAllowed(collection);
        bytes32 key = accountKey(collection, tokenId);
        address existing = _accounts[key].vault;
        if (existing != address(0)) revert AccountExists(key, existing);

        // A missing token reverts inside ownerOf; surface it as NotTokenOwner rather than a raw revert.
        address holder;
        try IERC721(collection).ownerOf(tokenId) returns (address h) {
            holder = h;
        } catch {}
        if (holder != msg.sender) revert NotTokenOwner(collection, tokenId, msg.sender);

        vault = Clones.cloneDeterministic(vaultImplementation, key);
        _accounts[key] = AccountInfo(collection, tokenId, vault, uint64(block.timestamp));
        AccountVault(vault).initialize(address(this), key);
        emit AccountCreated(key, collection, tokenId, vault, msg.sender);
    }
}
