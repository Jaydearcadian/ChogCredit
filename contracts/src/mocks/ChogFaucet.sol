// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockChogGenesis} from "./MockChogGenesis.sol";

/// @notice TEST / TESTNET ONLY. Hands one mock Chog to each address that asks, so anyone can try the app on a test
///         deployment. Needs MINTER_ROLE on the mock collection. Ids are handed out in order from `nextId`.
contract ChogFaucet {
    MockChogGenesis public immutable chog;
    uint256 public nextId;
    mapping(address => bool) public claimed;

    error AlreadyClaimed();
    error SoldOut();

    event Claimed(address indexed to, uint256 tokenId);

    constructor(MockChogGenesis chog_, uint256 firstId) {
        chog = chog_;
        nextId = firstId;
    }

    function claim() external returns (uint256 id) {
        if (claimed[msg.sender]) revert AlreadyClaimed();
        id = nextId;
        if (id > chog.MAX_SUPPLY()) revert SoldOut();
        claimed[msg.sender] = true;
        nextId = id + 1;
        chog.mint(msg.sender, id);
        emit Claimed(msg.sender, id);
    }
}
