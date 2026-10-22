// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChogAccountRegistry} from "../../src/core/ChogAccountRegistry.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";

interface IChogGenesis {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function supportsInterface(bytes4 id) external view returns (bool);
}

/// @dev Minimal ERC-721 receiver standing in for the future escrow. Not production code.
interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

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

    /// @dev The registry, pointed at the real collection, opens accounts for real holders (plain and 7702-delegated)
    /// and refuses everyone else.
    function testRegistryOpensAccountsForRealHolders() external onlyFork {
        address[] memory cols = new address[](1);
        cols[0] = CHOG;
        ChogAccountRegistry registry = new ChogAccountRegistry(cols, new address[](0), address(this), address(0));

        for (uint256 id = 1; id <= 2; id++) {
            address holder = chog.ownerOf(id);
            vm.prank(holder);
            address vault = registry.createAccount(CHOG, id);
            assertEq(vault, registry.predictVault(CHOG, id));
            bytes32 key = registry.accountKey(CHOG, id);
            assertTrue(registry.isController(key, holder));
            assertFalse(registry.isController(key, address(0xBAD)));
            assertEq(AccountVault(vault).key(), key);
        }

        // someone who is not the holder cannot open an account for token 3
        vm.prank(address(0xBAD));
        vm.expectRevert();
        registry.createAccount(CHOG, 3);
    }

    /// @dev Gate C against the REAL collection: open, escrow, prove nobody can move the Chog, release.
    /// Tokens 1 (plain EOA) and 2 (7702-delegated EOA) are the sampled holders.
    function testLiveEscrowRoundTrip_realCollection() external onlyFork {
        address[] memory cols = new address[](1);
        cols[0] = CHOG;
        ChogAccountRegistry registry = new ChogAccountRegistry(cols, new address[](0), address(this), address(0));
        ChogCreditEscrow escrow = ChogCreditEscrow(address(registry.escrow()));

        for (uint256 id = 1; id <= 2; id++) {
            address holder = chog.ownerOf(id);
            bytes32 key = registry.accountKey(CHOG, id);

            vm.startPrank(holder);
            registry.createAccount(CHOG, id);
            assertFalse(registry.canAcceptAssets(key), "wallet-held accounts hold nothing");
            chog.safeTransferFrom(holder, address(escrow), id);
            vm.stopPrank();

            assertEq(chog.ownerOf(id), address(escrow));
            assertEq(escrow.beneficialOwnerOf(key), holder);
            assertTrue(registry.canAcceptAssets(key));
            assertTrue(registry.isController(key, holder));

            // the previous owner (and an unrelated address) can no longer move the live token
            vm.prank(holder);
            vm.expectRevert();
            chog.transferFrom(holder, address(0xBEEF), id);
            vm.prank(address(0xBAD));
            vm.expectRevert();
            escrow.release(CHOG, id, address(0xBAD));

            vm.prank(holder);
            escrow.release(CHOG, id, holder);
            assertEq(chog.ownerOf(id), holder, "the real Chog came back");
            assertEq(uint8(registry.releaseBlocker(key)), uint8(ReleaseBlocker.None));
        }
    }

    address internal constant REAL_USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    ChogAccountRegistry internal liveRegistry;
    ChogCreditEscrow internal liveEscrow;
    AccountTransferCoordinator internal liveCoord;
    AccountVault internal liveVault;

    function _liveFundedAccount(uint256 id, address seller) internal {
        address[] memory cols = new address[](1);
        cols[0] = CHOG;
        address[] memory toks = new address[](1);
        toks[0] = REAL_USDC;
        liveRegistry = new ChogAccountRegistry(cols, toks, address(this), address(0));
        liveEscrow = ChogCreditEscrow(address(liveRegistry.escrow()));
        liveCoord = AccountTransferCoordinator(liveEscrow.coordinator());

        deal(REAL_USDC, seller, 250e6);
        vm.startPrank(seller);
        liveVault = AccountVault(liveRegistry.createAccount(CHOG, id));
        chog.safeTransferFrom(seller, address(liveEscrow), id);
        IERC20Min(REAL_USDC).approve(address(liveVault), 250e6);
        liveVault.depositERC20(REAL_USDC, 250e6);
        vm.stopPrank();
    }

    function _liveSignedSale(uint256 id, address seller, address buyer, uint256 buyerPk)
        internal
        view
        returns (AccountTransferCoordinator.Acceptance memory a, bytes memory sig)
    {
        a = AccountTransferCoordinator.Acceptance({
            key: liveRegistry.accountKey(CHOG, id),
            seller: seller,
            buyer: buyer,
            paymentToken: REAL_USDC,
            price: 100e6,
            stateNonce: liveVault.stateNonce(),
            epoch: liveEscrow.epochOf(liveRegistry.accountKey(CHOG, id)),
            deadline: block.timestamp + 1 days,
            salt: 1
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPk, liveCoord.hashAcceptance(a));
        sig = abi.encodePacked(r, s, v);
    }

    /// @dev Package sale on the real collection, funded and paid with the REAL Circle USDC contract on Monad.
    function testLiveSale_realChog_realUsdc() external onlyFork {
        assertEq(IERC20Min(REAL_USDC).decimals(), 6);
        uint256 id = 1;
        address seller = chog.ownerOf(id);
        (address buyer, uint256 buyerPk) = makeAddrAndKey("liveBuyer");
        _liveFundedAccount(id, seller);
        assertEq(liveVault.accounted(REAL_USDC), 250e6);

        deal(REAL_USDC, buyer, 100e6);
        vm.prank(buyer);
        IERC20Min(REAL_USDC).approve(address(liveCoord), 100e6);
        (AccountTransferCoordinator.Acceptance memory a, bytes memory sig) = _liveSignedSale(id, seller, buyer, buyerPk);

        uint256 sellerBefore = IERC20Min(REAL_USDC).balanceOf(seller);
        vm.prank(seller);
        liveCoord.executeSale(a, sig);

        bytes32 key = a.key;
        assertEq(liveEscrow.beneficialOwnerOf(key), buyer);
        assertEq(chog.ownerOf(id), address(liveEscrow), "the real Chog never left escrow");
        assertEq(IERC20Min(REAL_USDC).balanceOf(seller) - sellerBefore, 100e6, "seller paid in real USDC");
        assertEq(liveVault.accounted(REAL_USDC), 250e6, "portfolio moved with the Chog");

        vm.startPrank(buyer);
        liveVault.withdrawERC20(REAL_USDC, 250e6, buyer);
        liveEscrow.release(CHOG, id, buyer);
        vm.stopPrank();
        assertEq(chog.ownerOf(id), buyer);
        assertEq(IERC20Min(REAL_USDC).balanceOf(buyer), 250e6);
    }
}
