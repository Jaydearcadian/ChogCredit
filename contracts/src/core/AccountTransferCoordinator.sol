// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {AccountVault} from "./AccountVault.sol";
import {IChogAccountRegistry, IChogCreditEscrow, ReleaseBlocker} from "./interfaces/IChogAccountRegistry.sol";
import {IDebtSalePool} from "./interfaces/IDebtSalePool.sol";

/// @title AccountTransferCoordinator
/// @notice Atomic sale of a funded, escrowed Chog account (the "package") from its beneficial owner to a buyer who
///         signed exactly what they are buying. The Chog stays in escrow; only the beneficial owner changes, so the
///         assets and the vault move with the Chog and never separate from it.
/// @dev Two sale paths. `executeSale` is DEBT-FREE ONLY: it reverts if the credit module reports any debt, pending
///      operation or failure. `executeDebtSale` sells an account together with its debt (see
///      docs/DEBT_BEARING_SALES_SPEC.md): the buyer signs ceilings and floors for debt, collateral value and health, and
///      may have part of the payment repay the debt first. Created by the escrow's constructor; only the escrow trusts it.
///      The buyer's acceptance binds: account key, seller, buyer, payment token, price, the vault's state nonce
///      (so any deposit/withdrawal/sweep after signing voids it), the escrow ownership epoch (so an ownership
///      change and change-back cannot revive an old acceptance), a deadline and a salt, under an EIP-712 domain that
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
        uint256 epoch;
        uint256 deadline;
        uint256 salt;
    }

    struct DebtAcceptance {
        bytes32 key;
        address seller;
        address buyer;
        address paymentToken;
        uint256 price; // total paid by the buyer; `debtRepay` of it goes to the pool, the rest to the seller
        uint256 stateNonce;
        uint256 epoch;
        uint256 deadline;
        uint256 salt;
        address pool; // must be the bound credit module
        uint256 maxDebt; // debt after any payoff must not exceed this (loan-token units)
        uint256 minCollateralValue; // counted collateral value must be at least this (loan-token units)
        uint256 minHealthBps; // liquidationValue / debt after payoff must be at least this
        uint256 debtRepay; // repaid from the buyer's payment before the transfer
    }

    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "Acceptance(bytes32 key,address seller,address buyer,address paymentToken,uint256 price,uint256 stateNonce,uint256 epoch,uint256 deadline,uint256 salt)"
    );
    bytes32 public constant DEBT_ACCEPTANCE_TYPEHASH = keccak256(
        "DebtAcceptance(bytes32 key,address seller,address buyer,address paymentToken,uint256 price,uint256 stateNonce,uint256 epoch,uint256 deadline,uint256 salt,address pool,uint256 maxDebt,uint256 minCollateralValue,uint256 minHealthBps,uint256 debtRepay)"
    );

    /// @dev A sale never hands over a position that is already liquidatable.
    uint256 internal constant MIN_SALE_HEALTH_BPS = 10_000;

    IChogAccountRegistry public immutable registry;
    IChogCreditEscrow public immutable escrow;
    mapping(bytes32 => bool) public used;

    error NotSeller();
    error SellerNotBeneficialOwner();
    error BadParties();
    error Expired(uint256 deadline);
    error AlreadyUsed(bytes32 digest);
    error StateChanged(uint256 signed, uint256 current);
    error EpochChanged(uint256 signed, uint256 current);
    error HasLiabilities(ReleaseBlocker why);
    error InvalidSignature();
    error PaymentShortfall(uint256 expected, uint256 received);
    error NotBuyer();
    error NoDebtToSell();
    error WrongPool(address signed, address bound);
    error PendingOperation();
    error PriceUnavailable();
    error AlreadyLiquidatable(uint256 healthBps);
    error RepayNeedsLoanToken(address paymentToken, address loanToken);
    error RepayExceedsPrice(uint256 debtRepay, uint256 price);
    error RepayExceedsDebt(uint256 debtRepay, uint256 debt);
    error RepayMismatch(uint256 expected, uint256 actual);
    error DebtAboveCeiling(uint256 debt, uint256 maxDebt);
    error CollateralBelowFloor(uint256 value, uint256 minValue);
    error HealthBelowFloor(uint256 healthBps, uint256 minHealthBps);

    event SaleExecuted(
        bytes32 indexed key,
        address indexed seller,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        bytes32 digest
    );
    event DebtSaleExecuted(
        bytes32 indexed key,
        address indexed seller,
        address indexed buyer,
        address paymentToken,
        uint256 price,
        uint256 debtRepay,
        uint256 debtAfter,
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
                    a.epoch,
                    a.deadline,
                    a.salt
                )
            )
        );
    }

    function hashDebtAcceptance(DebtAcceptance calldata a) public view returns (bytes32) {
        // Every member is a static 32-byte word, so concatenating two encodings equals one encoding of all fifteen
        // words; split only to stay within the stack limit.
        return _hashTypedDataV4(
            keccak256(
                bytes.concat(
                    abi.encode(
                        DEBT_ACCEPTANCE_TYPEHASH,
                        a.key,
                        a.seller,
                        a.buyer,
                        a.paymentToken,
                        a.price,
                        a.stateNonce,
                        a.epoch
                    ),
                    abi.encode(a.deadline, a.salt, a.pool, a.maxDebt, a.minCollateralValue, a.minHealthBps, a.debtRepay)
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
        // Never hand an account to the protocol's own contracts: nothing there could ever act as its owner.
        if (
            a.buyer == address(this) || a.buyer == address(escrow) || a.buyer == address(registry)
                || a.buyer == registry.accountInfo(a.key).vault
        ) revert BadParties();
        if (escrow.beneficialOwnerOf(a.key) != a.seller) revert SellerNotBeneficialOwner();
        if (block.timestamp > a.deadline) revert Expired(a.deadline);

        bytes32 digest = hashAcceptance(a);
        if (used[digest]) revert AlreadyUsed(digest);
        if (!_validSignature(a.buyer, digest, buyerSignature)) revert InvalidSignature();

        address vault = registry.accountInfo(a.key).vault;
        uint256 nonce = AccountVault(vault).stateNonce();
        if (nonce != a.stateNonce) revert StateChanged(a.stateNonce, nonce);
        uint256 epoch = escrow.epochOf(a.key);
        if (epoch != a.epoch) revert EpochChanged(a.epoch, epoch);
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

    /// @notice Seller executes the sale of an account that carries debt, on terms the buyer signed. Atomic.
    /// @dev Order: consent and state checks, then payoff, then the bounds on the result, then the ownership change and
    ///      payment. The debt itself needs no transfer: it is recorded against the account, and control of the account
    ///      follows the beneficial owner.
    function executeDebtSale(DebtAcceptance calldata a, bytes calldata buyerSignature) external nonReentrant {
        _checkParties(a.key, a.seller, a.buyer, a.deadline);
        bytes32 digest = hashDebtAcceptance(a);
        _checkConsentAndState(a.key, a.buyer, digest, buyerSignature, a.stateNonce, a.epoch);

        if (registry.liabilityBlocker(a.key) != ReleaseBlocker.HasDebt) revert NoDebtToSell();
        address bound = registry.creditModule();
        if (a.pool != bound) revert WrongPool(a.pool, bound);
        IDebtSalePool pool = IDebtSalePool(bound);
        if (pool.hasPendingOperation(a.key)) revert PendingOperation();

        IDebtSalePool.AccountData memory before = pool.accountData(a.key);
        if (!before.priceOk) revert PriceUnavailable();
        if (before.healthFactorBps < MIN_SALE_HEALTH_BPS) revert AlreadyLiquidatable(before.healthFactorBps);
        if (a.debtRepay > a.price) revert RepayExceedsPrice(a.debtRepay, a.price);

        used[digest] = true; // effects first
        if (a.debtRepay != 0) _payOff(pool, a, before.debt);
        _checkBounds(pool, a);

        escrow.transferBeneficialOwnership(a.key, a.buyer);
        _paySeller(a.paymentToken, a.buyer, a.seller, a.price - a.debtRepay);
        emit DebtSaleExecuted(
            a.key, a.seller, a.buyer, a.paymentToken, a.price, a.debtRepay, pool.accountData(a.key).debt, digest
        );
    }

    function _checkParties(bytes32 key, address seller, address buyer, uint256 deadline) internal view {
        if (msg.sender != seller) revert NotSeller();
        if (buyer == address(0) || buyer == seller) revert BadParties();
        // Never hand an account to the protocol's own contracts: nothing there could ever act as its owner.
        if (
            buyer == address(this) || buyer == address(escrow) || buyer == address(registry)
                || buyer == registry.accountInfo(key).vault
        ) revert BadParties();
        if (escrow.beneficialOwnerOf(key) != seller) revert SellerNotBeneficialOwner();
        if (block.timestamp > deadline) revert Expired(deadline);
    }

    function _checkConsentAndState(
        bytes32 key,
        address buyer,
        bytes32 digest,
        bytes calldata sig,
        uint256 signedNonce,
        uint256 signedEpoch
    ) internal view {
        if (used[digest]) revert AlreadyUsed(digest);
        if (!_validSignature(buyer, digest, sig)) revert InvalidSignature();
        uint256 nonce = AccountVault(registry.accountInfo(key).vault).stateNonce();
        if (nonce != signedNonce) revert StateChanged(signedNonce, nonce);
        uint256 epoch = escrow.epochOf(key);
        if (epoch != signedEpoch) revert EpochChanged(signedEpoch, epoch);
    }

    function _payOff(IDebtSalePool pool, DebtAcceptance calldata a, uint256 debt) internal {
        address loan = pool.loanToken();
        if (a.paymentToken != loan) revert RepayNeedsLoanToken(a.paymentToken, loan);
        if (a.debtRepay > debt) revert RepayExceedsDebt(a.debtRepay, debt);
        IERC20 token = IERC20(loan);
        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(a.buyer, address(this), a.debtRepay);
        uint256 got = token.balanceOf(address(this)) - beforeBal;
        if (got != a.debtRepay) revert PaymentShortfall(a.debtRepay, got);
        token.forceApprove(address(pool), a.debtRepay);
        uint256 repaid = pool.repay(a.key, a.debtRepay);
        token.forceApprove(address(pool), 0);
        if (repaid != a.debtRepay) revert RepayMismatch(a.debtRepay, repaid);
    }

    function _checkBounds(IDebtSalePool pool, DebtAcceptance calldata a) internal view {
        IDebtSalePool.AccountData memory d = pool.accountData(a.key);
        if (!d.priceOk) revert PriceUnavailable();
        if (d.debt > a.maxDebt) revert DebtAboveCeiling(d.debt, a.maxDebt);
        if (d.collateralValue < a.minCollateralValue) {
            revert CollateralBelowFloor(d.collateralValue, a.minCollateralValue);
        }
        if (d.healthFactorBps < a.minHealthBps) revert HealthBelowFloor(d.healthFactorBps, a.minHealthBps);
        if (d.healthFactorBps < MIN_SALE_HEALTH_BPS) revert AlreadyLiquidatable(d.healthFactorBps);
    }

    function _paySeller(address paymentToken, address buyer, address seller, uint256 amount) internal {
        if (amount == 0) return;
        IERC20 token = IERC20(paymentToken);
        uint256 beforeBal = token.balanceOf(seller);
        token.safeTransferFrom(buyer, seller, amount);
        uint256 got = token.balanceOf(seller) - beforeBal;
        if (got != amount) revert PaymentShortfall(amount, got);
    }

    /// @notice The buyer can void a signed acceptance before the seller uses it.
    function cancel(Acceptance calldata a) external {
        if (msg.sender != a.buyer) revert NotBuyer();
        bytes32 digest = hashAcceptance(a);
        used[digest] = true;
        emit AcceptanceCancelled(digest, msg.sender);
    }

    /// @notice Same, for a debt-bearing acceptance.
    function cancelDebt(DebtAcceptance calldata a) external {
        if (msg.sender != a.buyer) revert NotBuyer();
        bytes32 digest = hashDebtAcceptance(a);
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
