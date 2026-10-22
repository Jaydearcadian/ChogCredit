// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice One Chog Credit account: the original NFT (collection + tokenId) and its vault.
struct AccountInfo {
    address collection;
    uint256 tokenId;
    address vault;
    uint64 createdAt;
}

interface IChogAccountRegistry {
    error ZeroAddress();
    error EmptyAllowlist();
    error DuplicateEntry(address entry);
    error CollectionNotAllowed(address collection);
    error NotTokenOwner(address collection, uint256 tokenId, address caller);
    error AccountExists(bytes32 key, address vault);
    error UnknownAccount(bytes32 key);

    event AccountCreated(
        bytes32 indexed key, address indexed collection, uint256 indexed tokenId, address vault, address creator
    );

    function accountKey(address collection, uint256 tokenId) external view returns (bytes32);
    function accountInfo(bytes32 key) external view returns (AccountInfo memory);
    function vaultOf(address collection, uint256 tokenId) external view returns (address);
    function predictVault(address collection, uint256 tokenId) external view returns (address);
    function createAccount(address collection, uint256 tokenId) external returns (address vault);

    /// @notice True if `who` currently controls the account. Fails closed: any revert or odd answer from the
    /// collection yields false.
    function isController(bytes32 key, address who) external view returns (bool);
    function isCollectionAllowed(address collection) external view returns (bool);
    function isTokenAllowed(address token) external view returns (bool);
    /// @notice Whether the account may accept assets in its current custody mode.
    function canAcceptAssets(bytes32 key) external view returns (bool);
}
