// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IChogDebtView {
    function debtOf(uint256 accountId) external view returns (uint256);
}

/// @notice NFT identity for one Chog financial account.
/// @dev Debt-bearing transfers are deliberately blocked in this MVP. Transfer only after full repayment.
contract ChogPositionNFT is ERC721, Ownable {
    uint256 public nextTokenId = 1;
    address public creditFacility;

    error OnlyCreditFacility();
    error CreditFacilityAlreadySet();
    error ZeroAddress();
    error DebtActive(uint256 accountId, uint256 debt);

    event CreditFacilitySet(address indexed creditFacility);

    constructor(address initialOwner) ERC721("Chog Position Account", "CHOG-POS") Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
    }

    function setCreditFacility(address facility) external onlyOwner {
        if (facility == address(0)) revert ZeroAddress();
        if (creditFacility != address(0)) revert CreditFacilityAlreadySet();
        creditFacility = facility;
        emit CreditFacilitySet(facility);
    }

    function mint(address to) external returns (uint256 accountId) {
        if (msg.sender != creditFacility) revert OnlyCreditFacility();
        if (to == address(0)) revert ZeroAddress();
        accountId = nextTokenId++;
        _safeMint(to, accountId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        // Mints and burns are not transfers. Debt-bearing secondary sales are not supported in this MVP.
        if (from != address(0) && to != address(0) && from != to && creditFacility != address(0)) {
            uint256 debt = IChogDebtView(creditFacility).debtOf(tokenId);
            if (debt != 0) revert DebtActive(tokenId, debt);
        }
        return super._update(to, tokenId, auth);
    }
}
