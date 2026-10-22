// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice One Chog Credit account: the original NFT (collection + tokenId) and its vault.
struct AccountInfo {
    address collection;
    uint256 tokenId;
    address vault;
    uint64 createdAt;
}

/// @notice Why the original NFT cannot currently leave escrow.
enum ReleaseBlocker {
    None,
    UnknownAccount,
    HasAssets,
    HasDebt,
    PendingOperation,
    ModuleUnavailable
}

/// @notice Implemented by the credit pool (Gate D). Reports liabilities the account must clear before release.
interface ICreditModule {
    function debtOf(bytes32 key) external view returns (uint256);
    function hasPendingOperation(bytes32 key) external view returns (bool);
}

interface IChogCreditEscrow {
    function beneficialOwnerOf(bytes32 key) external view returns (address);
    function isEscrowed(bytes32 key) external view returns (bool);
    function coordinator() external view returns (address);
    /// @notice Only the transfer coordinator may call this. Moves the beneficial owner of an escrowed account.
    function transferBeneficialOwnership(bytes32 key, address newOwner) external;
}

interface IChogAccountRegistry {
    error ZeroAddress();
    error EmptyAllowlist();
    error DuplicateEntry(address entry);
    error CollectionNotAllowed(address collection);
    error NotTokenOwner(address collection, uint256 tokenId, address caller);
    error AccountExists(bytes32 key, address vault);
    error UnknownAccount(bytes32 key);
    error NotBinder();
    error ModuleAlreadyBound();

    event AccountCreated(
        bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address vault, address creator
    );
    event CreditModuleBound(address indexed module);

    function accountKey(address collection, uint256 tokenId) external view returns (bytes32);
    function accountExists(bytes32 key) external view returns (bool);
    function accountInfo(bytes32 key) external view returns (AccountInfo memory);
    function vaultOf(address collection, uint256 tokenId) external view returns (address);
    function predictVault(address collection, uint256 tokenId) external view returns (address);
    function createAccount(address collection, uint256 tokenId) external returns (address vault);

    function escrow() external view returns (IChogCreditEscrow);
    function creditModule() external view returns (address);

    /// @notice True if `who` currently controls the account. While the NFT is escrowed that is the beneficial owner;
    /// otherwise it is the collection's live `ownerOf`. Fails closed on any revert.
    function isController(bytes32 key, address who) external view returns (bool);
    function isCollectionAllowed(address collection) external view returns (bool);
    function isTokenAllowed(address token) external view returns (bool);
    /// @notice The account may hold assets only while its Chog is in escrow.
    function canAcceptAssets(bytes32 key) external view returns (bool);
    /// @notice Debt reported by the credit module; fails closed (max) if the module reverts. Zero if none is bound.
    function debtOf(bytes32 key) external view returns (uint256);
    function releaseBlocker(bytes32 key) external view returns (ReleaseBlocker);
    /// @notice Like `releaseBlocker` but ignores held assets: only debt, pending operations and module failure.
    function liabilityBlocker(bytes32 key) external view returns (ReleaseBlocker);
}
