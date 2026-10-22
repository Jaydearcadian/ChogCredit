// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice TEST / TESTNET ONLY. Mirrors what is observable about the live Chog Genesis contract
///         (0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763): ERC-721 + ERC-2981 + role-based admin, ids 1..1969,
///         not enumerable, no transfer validator. It is NOT the real collection and proves nothing about it.
contract MockChogGenesis is ERC721, ERC2981, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant MAX_SUPPLY = 1969;

    uint256 public totalSupply;

    error InvalidTokenId(uint256 tokenId);

    constructor(address admin) ERC721("Chog Genesis", "CHOG") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _setDefaultRoyalty(admin, 500);
    }

    function mint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert InvalidTokenId(tokenId);
        _mint(to, tokenId);
        ++totalSupply;
    }

    function supportsInterface(bytes4 id) public view override(ERC721, ERC2981, AccessControl) returns (bool) {
        return super.supportsInterface(id);
    }
}
