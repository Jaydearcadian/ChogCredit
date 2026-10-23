// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IChogAccountRegistry, IChogCreditEscrow, ReleaseBlocker} from "./interfaces/IChogAccountRegistry.sol";
import {AccountTransferCoordinator} from "./AccountTransferCoordinator.sol";

/// @title ChogCreditEscrow
/// @notice Holds the original Chog NFT while its account carries assets, positions or debt, and records the
///         beneficial owner. `ownerOf(tokenId)` on the collection is this contract while escrowed; the beneficial
///         owner is recorded here.
/// @dev Trust boundary. There is no owner, admin, pause or rescue function. The only way out is `release`, callable
///      by the beneficial owner when the account is empty and clear of liabilities, or the package sale in the
///      `coordinator` that this contract creates. Deposit is by `safeTransferFrom` into `onERC721Received`.
///      The ONE privileged role is the optional immutable `rescuer`: it may recover tokens that are held here but
///      unrecorded (sent with plain `transferFrom`) after a public `RESCUE_DELAY`, and it can never touch a recorded
///      token. It cannot be rotated, so it should be a multisig/timelock contract; address(0) disables it. A rescuer
///      key that is lost simply ends rescue; one that is compromised can take future stranded tokens, never recorded
///      ones. Created by the registry in its constructor. The UI must only use `safeTransferFrom`.
contract ChogCreditEscrow is IChogCreditEscrow, IERC721Receiver, ReentrancyGuard {
    uint256 public constant RESCUE_DELAY = 3 days;

    IChogAccountRegistry public immutable registry;
    address public immutable coordinator;
    address public immutable rescuer;
    mapping(bytes32 => address) private _beneficial;
    mapping(bytes32 => uint256) public epochOf;

    struct Rescue {
        address to;
        uint64 readyAt;
    }

    mapping(bytes32 => Rescue) public rescues;

    error NotRegistry();
    error CollectionNotAllowed(address collection);
    error AccountNotOpen(bytes32 key);
    error AlreadyEscrowed(bytes32 key);
    error NotHeld(address collection, uint256 tokenId);
    error ZeroAddress();
    error NotEscrowed(bytes32 key);
    error NotBeneficialOwner(bytes32 key, address caller);
    error ReleaseBlocked(bytes32 key, ReleaseBlocker reason);
    error NotCoordinator();
    error NotRescuer();
    error RescueDisabled();
    error NotStranded(address collection, uint256 tokenId);
    error RescueNotReady(uint256 readyAt);
    error NoRescuePending();
    error RescueAlreadyPending(address collection, uint256 tokenId);

    event Escrowed(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address beneficialOwner);
    event Released(bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address to);
    event BeneficialOwnerChanged(bytes32 indexed key, address indexed from, address indexed to);
    event RescueRequested(address indexed collection, uint256 indexed tokenId, address to, uint256 readyAt);
    event RescueCancelled(address indexed collection, uint256 indexed tokenId);
    event RescueExecuted(address indexed collection, uint256 indexed tokenId, address to);

    constructor(address registry_, address rescuer_) {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = IChogAccountRegistry(registry_);
        rescuer = rescuer_;
        coordinator = address(new AccountTransferCoordinator(registry_, address(this)));
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
        ++epochOf[key];
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
        ++epochOf[key];
        emit Released(key, collection, tokenId, to);
        // transferFrom, not safeTransferFrom: no callback into `to`. EIP-7702-delegated EOAs (common Chog holders)
        // may run a delegate that lacks the ERC-721 receiver hook, and marketplaces such as Seaport also use
        // transferFrom. The beneficial owner chooses `to` and bears the risk of a non-receiving contract.
        IERC721(collection).transferFrom(address(this), to, tokenId);
    }

    // ---------------------------------------------------------------- package sale hook

    /// @notice Called only by the transfer coordinator after it has verified buyer consent, payment and account state.
    function transferBeneficialOwnership(bytes32 key, address newOwner) external {
        if (msg.sender != coordinator) revert NotCoordinator();
        address old = _beneficial[key];
        if (old == address(0)) revert NotEscrowed(key);
        if (newOwner == address(0)) revert ZeroAddress();
        _beneficial[key] = newOwner;
        ++epochOf[key];
        emit BeneficialOwnerChanged(key, old, newOwner);
    }

    // ---------------------------------------------------------------- stranded-token rescue

    /// @dev A token is "stranded" when the collection says this contract holds it but no beneficial owner is recorded.
    ///      A recorded token can never pass this check, so the rescuer has no power over any account.
    function _requireStranded(address collection, uint256 tokenId) internal view returns (bytes32 key) {
        if (rescuer == address(0)) revert RescueDisabled();
        if (msg.sender != rescuer) revert NotRescuer();
        key = registry.accountKey(collection, tokenId);
        if (_beneficial[key] != address(0)) revert NotStranded(collection, tokenId);
        // A burned or missing token makes ownerOf revert; report it as not stranded rather than bubbling the error.
        try IERC721(collection).ownerOf(tokenId) returns (address holder) {
            if (holder != address(this)) revert NotStranded(collection, tokenId);
        } catch {
            revert NotStranded(collection, tokenId);
        }
    }

    function requestRescue(address collection, uint256 tokenId, address to) external {
        if (to == address(0)) revert ZeroAddress();
        bytes32 key = _requireStranded(collection, tokenId);
        // No silent re-request: the public delay must not be restartable or retargetable without a visible cancel.
        if (rescues[key].readyAt != 0) revert RescueAlreadyPending(collection, tokenId);
        uint64 readyAt = uint64(block.timestamp + RESCUE_DELAY);
        rescues[key] = Rescue(to, readyAt);
        emit RescueRequested(collection, tokenId, to, readyAt);
    }

    function cancelRescue(address collection, uint256 tokenId) external {
        if (rescuer == address(0)) revert RescueDisabled();
        if (msg.sender != rescuer) revert NotRescuer();
        bytes32 key = registry.accountKey(collection, tokenId);
        if (rescues[key].readyAt == 0) revert NoRescuePending();
        delete rescues[key];
        emit RescueCancelled(collection, tokenId);
    }

    function executeRescue(address collection, uint256 tokenId) external nonReentrant {
        bytes32 key = _requireStranded(collection, tokenId);
        Rescue memory r = rescues[key];
        if (r.readyAt == 0) revert NoRescuePending();
        if (block.timestamp < r.readyAt) revert RescueNotReady(r.readyAt);
        delete rescues[key];
        emit RescueExecuted(collection, tokenId, r.to);
        IERC721(collection).transferFrom(address(this), r.to, tokenId);
    }
}
