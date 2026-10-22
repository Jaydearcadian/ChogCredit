// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IChogAccountRegistry, IChogCreditEscrow, ReleaseBlocker} from "./interfaces/IChogAccountRegistry.sol";

interface IVaultNonce {
    function stateNonce() external view returns (uint256);
}

/// @title AccountTransferCoordinator
/// @notice Atomic sale of a funded, escrowed Chog account (the "package") from its beneficial owner to a buyer who
///         signed exactly what they are buying. The Chog stays in escrow; only the beneficial owner changes, so the
///         assets and the vault move with the Chog and never separate from it.
/// @dev DEBT-FREE SALES ONLY. A sale reverts if the credit module reports any debt, pending operation or failure.
///      Debt-bearing transfer needs the credit pool and extra signed fields (debt ceiling, health floor) and is not
///      implemented. Created by the escrow's constructor; only the escrow trusts it.
///      The buyer's acceptance binds: account key, seller, buyer, payment token, price, the vault's state nonce
///      (so any deposit/withdrawal after signing voids it), a deadline and a salt, under an EIP-712 domain that
///      includes the chain ID and this contract. Signatures are accepted from the buyer's key directly (this is what
///      makes EIP-7702-delegated EOAs work) or through ERC-1271 for smart-contract wallets.
contract AccountTransferCoordinator is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Acceptance {
        bytes32 key;
        address seller;
        address buyer;
        address paymentToken;
        uint256 price;
        uint256 stateNonce;
        uint256 deadline;
        uint256 salt;
    }

    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "Acceptance(bytes32 key,address seller,address buyer,address paymentToken,uint256 price,uint256 stateNonce,uint256 deadline,uint256 salt)"
    );

    IChogAccountRegistry public immutable registry;
    IChogCreditEscrow public immutable escrow;
    mapping(bytes32 => bool) public used;

    error NotSeller();
    error SellerNotBeneficialOwner();
    error BadParties();
    error Expired(uint256 deadline);
    error AlreadyUsed(bytes32 digest);
    error StateChanged(uint256 signed, uint256 current);
    error HasLiabilities(ReleaseBlocker why);
    error InvalidSignature();
    error PaymentShortfall(uint256 expected, uint256 received);
    error NotBuyer();

    event SaleExecuted(
        bytes32 indexed key,
        address indexed seller,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        bytes32 digest
    );
    event AcceptanceCancelled(bytes32 indexed digest, address indexed buyer);

    constructor(address registry_, address escrow_) EIP712("ChogCreditTransfer", "1") {
        registry = IChogAccountRegistry(registry_);
        escrow = IChogCreditEscrow(escrow_);
    }

    function hashAcceptance(Acceptance calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ACCEPTANCE_TYPEHASH,
                    a.key,
                    a.seller,
                    a.buyer,
                    a.paymentToken,
                    a.price,
                    a.stateNonce,
                    a.deadline,
                    a.salt
                )
            )
        );
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Seller executes a sale the buyer has signed. Everything succeeds together or nothing changes.
    function executeSale(Acceptance calldata a, bytes calldata buyerSignature) external nonReentrant {
        if (msg.sender != a.seller) revert NotSeller();
        if (a.buyer == address(0) || a.buyer == a.seller) revert BadParties();
        if (escrow.beneficialOwnerOf(a.key) != a.seller) revert SellerNotBeneficialOwner();
        if (block.timestamp > a.deadline) revert Expired(a.deadline);

        bytes32 digest = hashAcceptance(a);
        if (used[digest]) revert AlreadyUsed(digest);
        if (!_validSignature(a.buyer, digest, buyerSignature)) revert InvalidSignature();

        address vault = registry.accountInfo(a.key).vault;
        uint256 nonce = IVaultNonce(vault).stateNonce();
        if (nonce != a.stateNonce) revert StateChanged(a.stateNonce, nonce);
        ReleaseBlocker why = registry.liabilityBlocker(a.key);
        if (why != ReleaseBlocker.None) revert HasLiabilities(why);

        used[digest] = true; // effects first
        escrow.transferBeneficialOwnership(a.key, a.buyer);

        if (a.price != 0) {
            IERC20 token = IERC20(a.paymentToken);
            uint256 beforeBal = token.balanceOf(a.seller);
            token.safeTransferFrom(a.buyer, a.seller, a.price);
            uint256 got = token.balanceOf(a.seller) - beforeBal;
            if (got != a.price) revert PaymentShortfall(a.price, got);
        }
        emit SaleExecuted(a.key, a.seller, a.buyer, a.paymentToken, a.price, digest);
    }

    /// @notice The buyer can void a signed acceptance before the seller uses it.
    function cancel(Acceptance calldata a) external {
        if (msg.sender != a.buyer) revert NotBuyer();
        bytes32 digest = hashAcceptance(a);
        used[digest] = true;
        emit AcceptanceCancelled(digest, msg.sender);
    }

    /// @dev Key signature first, then ERC-1271. Order matters: an EIP-7702-delegated EOA has code, and its delegate
    ///      may not implement ERC-1271, but its key can still sign.
    function _validSignature(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) return true;
        if (signer.code.length != 0) return SignatureChecker.isValidERC1271SignatureNow(signer, digest, sig);
        return false;
    }
}
