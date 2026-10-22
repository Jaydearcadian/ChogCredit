// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    IChogAccountRegistry,
    IChogCreditEscrow,
    ICreditModule,
    ReleaseBlocker,
    AccountInfo
} from "./interfaces/IChogAccountRegistry.sol";
import {AccountVault} from "./AccountVault.sol";
import {ChogCreditEscrow} from "./ChogCreditEscrow.sol";

/// @title ChogAccountRegistry
/// @notice Maps an existing Chog NFT (chainId, collection, tokenId) to exactly one portfolio vault. It never mints an
///         identity NFT. The collection and asset allowlists are fixed at deployment and have no setter.
/// @dev GATE C. A vault may hold assets only while its Chog is in `escrow` (deployed by this constructor), so a sale of
///      the NFT can never hand over a non-empty portfolio. Control is the beneficial owner while escrowed, otherwise
///      the collection's live `ownerOf`. The single privileged action is `bindCreditModule`: the deployer ("binder")
///      may bind the credit pool once so debt can block release and withdrawal. Production must make the binder a
///      multisig/timelock or bind the pool in the deployment transaction.
contract ChogAccountRegistry is IChogAccountRegistry {
    address public immutable vaultImplementation;
    IChogCreditEscrow public immutable escrow;
    address public immutable binder;
    address public creditModule;

    mapping(address => bool) public isCollectionAllowed;
    mapping(address => bool) public isTokenAllowed;
    mapping(bytes32 => AccountInfo) private _accounts;

    /// @param binder_ may bind the credit module once; use a deployment contract/multisig, or address(0) for none.
    /// @param rescuer_ may recover stranded (unrecorded) tokens from the escrow after a delay; address(0) disables it.
    constructor(address[] memory collections, address[] memory tokens, address binder_, address rescuer_) {
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
        binder = binder_;
        vaultImplementation = address(new AccountVault());
        escrow = IChogCreditEscrow(address(new ChogCreditEscrow(address(this), rescuer_)));
    }

    // ---------------------------------------------------------------- views

    function accountKey(address collection, uint256 tokenId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, collection, tokenId));
    }

    function accountExists(bytes32 key) external view returns (bool) {
        return _accounts[key].vault != address(0);
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
        address beneficial = escrow.beneficialOwnerOf(key);
        if (beneficial != address(0)) return beneficial == who;
        // Deliberately no `who.code.length` test: many Chog holders are EIP-7702-delegated EOAs and have code.
        try IERC721(info.collection).ownerOf(info.tokenId) returns (address holder) {
            return holder == who;
        } catch {
            return false;
        }
    }

    function canAcceptAssets(bytes32 key) external view returns (bool) {
        return escrow.isEscrowed(key);
    }

    function debtOf(bytes32 key) public view returns (uint256) {
        address module = creditModule;
        if (module == address(0)) return 0;
        try ICreditModule(module).debtOf(key) returns (uint256 d) {
            return d;
        } catch {
            return type(uint256).max; // fail closed
        }
    }

    function releaseBlocker(bytes32 key) external view returns (ReleaseBlocker) {
        address vault = _accounts[key].vault;
        if (vault == address(0)) return ReleaseBlocker.UnknownAccount;
        if (!AccountVault(vault).isEmpty()) return ReleaseBlocker.HasAssets;
        return liabilityBlocker(key);
    }

    function liabilityBlocker(bytes32 key) public view returns (ReleaseBlocker) {
        if (_accounts[key].vault == address(0)) return ReleaseBlocker.UnknownAccount;
        address module = creditModule;
        if (module == address(0)) return ReleaseBlocker.None;
        try ICreditModule(module).debtOf(key) returns (uint256 d) {
            if (d != 0) return ReleaseBlocker.HasDebt;
        } catch {
            return ReleaseBlocker.ModuleUnavailable;
        }
        try ICreditModule(module).hasPendingOperation(key) returns (bool pending) {
            if (pending) return ReleaseBlocker.PendingOperation;
        } catch {
            return ReleaseBlocker.ModuleUnavailable;
        }
        return ReleaseBlocker.None;
    }

    /// @notice One-time wiring of the credit pool. Only the deployer, only once, never zero.
    function bindCreditModule(address module) external {
        if (msg.sender != binder) revert NotBinder();
        if (creditModule != address(0)) revert ModuleAlreadyBound();
        if (module == address(0)) revert ZeroAddress();
        creditModule = module;
        emit CreditModuleBound(module);
    }

    // ---------------------------------------------------------------- create

    /// @notice Open the account for a Chog you currently hold. One account per (chain, collection, tokenId).
    function createAccount(address collection, uint256 tokenId) external returns (address vault) {
        if (!isCollectionAllowed[collection]) revert CollectionNotAllowed(collection);
        bytes32 key = accountKey(collection, tokenId);
        address existing = _accounts[key].vault;
        if (existing != address(0)) revert AccountExists(key, existing);

        // A missing token reverts inside ownerOf; surface it as NotTokenOwner rather than a raw revert.
        address holder = address(0);
        try IERC721(collection).ownerOf(tokenId) returns (address h) {
            holder = h;
        } catch {}
        if (holder != msg.sender) revert NotTokenOwner(collection, tokenId, msg.sender);

        vault = Clones.cloneDeterministic(vaultImplementation, key);
        _accounts[key] = AccountInfo(collection, tokenId, vault, uint64(block.timestamp));
        emit AccountCreated(key, collection, tokenId, vault, msg.sender);
        AccountVault(vault).initialize(address(this), key);
    }
}
