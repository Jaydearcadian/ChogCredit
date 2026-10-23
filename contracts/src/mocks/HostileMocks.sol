// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TEST ONLY. A look-alike "Chog" collection that lies about ownership, or reverts, on demand.
contract HostileCollection is ERC721 {
    address public ownerOverride;
    bool public revertOwnerOf;

    constructor() ERC721("Chog Genesis", "CHOG") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setLie(address who) external {
        ownerOverride = who;
    }

    function setRevert(bool on) external {
        revertOwnerOf = on;
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        if (revertOwnerOf) revert("hostile revert");
        if (ownerOverride != address(0)) return ownerOverride;
        return super.ownerOf(tokenId);
    }
}

/// @notice TEST ONLY. Burns 1% on every transfer, so the receiver gets less than requested.
contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

interface IVaultLike {
    function withdrawERC20(address token, uint256 amount, address to) external;
}

/// @notice TEST ONLY. Tries to re-enter the vault from inside `transferFrom`.
contract ReentrantToken is ERC20 {
    address public target;
    address public attacker;
    bool public armed;
    bool public reentryReverted;
    bytes public reentryReason;

    constructor() ERC20("Reentrant", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target_, address attacker_) external {
        target = target_;
        attacker = attacker_;
        armed = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (armed && to == target) {
            armed = false;
            try IVaultLike(target).withdrawERC20(address(this), 1, attacker) {}
            catch (bytes memory reason) {
                reentryReverted = true;
                reentryReason = reason;
            }
        }
    }
}
