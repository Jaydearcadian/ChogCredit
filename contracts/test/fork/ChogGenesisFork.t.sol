// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

interface IChogGenesis {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function supportsInterface(bytes4 id) external view returns (bool);
}

/// @dev Minimal ERC-721 receiver standing in for the future escrow. Not production code.
contract ForkReceiver {
    uint256 public received;

    function release(IChogGenesis token, uint256 tokenId, address to) external {
        token.safeTransferFrom(address(this), to, tokenId);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        received = tokenId;
        return this.onERC721Received.selector;
    }
}

/// @notice Live-collection checks against Monad mainnet. Skipped unless MONAD_MAINNET_RPC_URL is set.
/// Run: MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*" -vv
contract ChogGenesisForkTest is Test {
    address internal constant CHOG = 0xc96d31F8626c6D03Fae5dCD3d61e3FB9F4a73763;
    uint256 internal constant SAMPLE_TOKEN = 532;

    IChogGenesis internal chog = IChogGenesis(CHOG);
    bool internal forked;

    function setUp() external {
        string memory url = vm.envOr("MONAD_MAINNET_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
    }

    modifier onlyFork() {
        if (!forked) {
            vm.skip(true);
        }
        _;
    }

    function testLiveCollectionIdentity() external onlyFork {
        assertEq(block.chainid, 143, "not Monad mainnet");
        assertEq(chog.name(), "Chog Genesis");
        assertEq(chog.symbol(), "CHOG");
        assertEq(chog.totalSupply(), 1969);
        assertTrue(chog.supportsInterface(0x80ac58cd), "ERC721");
    }

    /// @dev Proves a holder can approve and safe-transfer a real Chog into a contract receiver and back out.
    /// Works for plain EOAs and for EIP-7702-delegated EOAs (code 0xef0100...), both common among Chog holders.
    function _roundTrip(uint256 tokenId) internal {
        address holder = chog.ownerOf(tokenId);
        ForkReceiver receiver = new ForkReceiver();

        vm.startPrank(holder);
        chog.approve(address(receiver), tokenId);
        assertEq(chog.getApproved(tokenId), address(receiver));
        chog.safeTransferFrom(holder, address(receiver), tokenId);
        vm.stopPrank();

        assertEq(chog.ownerOf(tokenId), address(receiver));
        assertEq(receiver.received(), tokenId);

        receiver.release(chog, tokenId, holder);
        assertEq(chog.ownerOf(tokenId), holder);
    }

    function testLiveChogCanBeEscrowedByAContract_plainEoaHolder() external onlyFork {
        _roundTrip(1);
    }

    function testLiveChogCanBeEscrowedByAContract_delegatedEoaHolder() external onlyFork {
        // Token 2's holder was a 7702-delegated EOA when this was written; the round trip must work either way.
        _roundTrip(2);
    }
}
