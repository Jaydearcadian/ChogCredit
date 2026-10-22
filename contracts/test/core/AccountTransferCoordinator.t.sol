// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CoreBase} from "./CoreBase.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {ChogCreditEscrow} from "../../src/core/ChogCreditEscrow.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ReleaseBlocker} from "../../src/core/interfaces/IChogAccountRegistry.sol";

/// @notice TEST ONLY. Minimal ERC-1271 smart wallet.
contract Wallet1271 {
    address public immutable owner;

    constructor(address o) {
        owner = o;
    }

    function isValidSignature(bytes32 h, bytes calldata sig) external view returns (bytes4) {
        (address r,,) = ECDSA.tryRecover(h, sig);
        return r == owner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function approveToken(IERC20 t, address spender, uint256 amt) external {
        t.approve(spender, amt);
    }
}

/// @notice TEST ONLY. Payment token that tries to call back into the coordinator during `transferFrom`.
contract ReentrantPayToken is ERC20 {
    address public target;
    bytes public data;
    bool public attempted;
    bytes public failure;

    constructor() ERC20("Pay", "PAY") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }

    function arm(address t, bytes calldata d) external {
        target = t;
        data = d;
    }

    function _update(address from, address to, uint256 v) internal override {
        super._update(from, to, v);
        if (target != address(0) && !attempted && from != address(0)) {
            attempted = true;
            (bool ok, bytes memory ret) = target.call(data);
            if (!ok) failure = ret;
        }
    }
}

contract AccountTransferCoordinatorTest is CoreBase {
    AccountTransferCoordinator internal coord;
    AccountVault internal vault;
    address internal buyer;
    uint256 internal buyerPk;
    address internal seller; // = alice, the beneficial owner

    function setUp() public override {
        super.setUp();
        coord = AccountTransferCoordinator(escrow.coordinator());
        seller = alice;
        (buyer, buyerPk) = makeAddrAndKey("buyer");

        vault = _open(alice, 1);
        deal(address(usdc), alice, 500e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.depositERC20(address(usdc), 500e6); // the portfolio being sold
        vm.stopPrank();

        deal(address(usdc), buyer, 1_000e6);
        vm.prank(buyer);
        usdc.approve(address(coord), type(uint256).max);
    }

    // ---- helpers
    function _acc(uint256 price, uint256 salt) internal view returns (AccountTransferCoordinator.Acceptance memory a) {
        a = AccountTransferCoordinator.Acceptance({
            key: _key(1),
            seller: seller,
            buyer: buyer,
            paymentToken: address(usdc),
            price: price,
            stateNonce: vault.stateNonce(),
            deadline: block.timestamp + 1 days,
            salt: salt
        });
    }

    /// @dev Memory structs alias on assignment; always copy before mutating a variant.
    function _clone(AccountTransferCoordinator.Acceptance memory a)
        internal
        pure
        returns (AccountTransferCoordinator.Acceptance memory c)
    {
        c = AccountTransferCoordinator.Acceptance(
            a.key, a.seller, a.buyer, a.paymentToken, a.price, a.stateNonce, a.deadline, a.salt
        );
    }

    function _sign(AccountTransferCoordinator.Acceptance memory a, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, coord.hashAcceptance(a));
        return abi.encodePacked(r, s, v);
    }

    function _sell(AccountTransferCoordinator.Acceptance memory a, bytes memory sig) internal {
        vm.prank(a.seller);
        coord.executeSale(a, sig);
    }

    // ---- happy path
    function test_sale_movesPackageAndPayment_chogNeverLeavesEscrow() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        bytes32 digest = coord.hashAcceptance(a);

        vm.expectEmit(true, true, true, true, address(coord));
        emit AccountTransferCoordinator.SaleExecuted(a.key, seller, buyer, address(usdc), 100e6, digest);
        _sell(a, sig);

        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
        assertEq(chog.ownerOf(1), address(escrow), "the Chog stays in escrow");
        assertEq(vault.accounted(address(usdc)), 500e6, "the portfolio is untouched");
        assertEq(usdc.balanceOf(seller), 100e6);
        assertEq(usdc.balanceOf(buyer), 900e6);
        assertTrue(coord.used(digest));
        assertTrue(registry.isController(_key(1), buyer));
        assertFalse(registry.isController(_key(1), seller));
    }

    function test_afterSale_newOwnerControlsVault_oldOwnerLocksOut() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        _sell(a, _sign(a, buyerPk));

        vm.prank(seller);
        vm.expectRevert(AccountVault.NotController.selector);
        vault.withdrawERC20(address(usdc), 1, seller);

        vm.prank(buyer);
        vault.withdrawERC20(address(usdc), 200e6, buyer);
        assertEq(usdc.balanceOf(buyer), 1_100e6);
    }

    function test_afterSale_chogCannotLeaveWhileAssetsRemain_butCanOnceEmpty() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(0, 1);
        _sell(a, _sign(a, buyerPk));
        bytes32 key = _key(1);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.ReleaseBlocked.selector, key, ReleaseBlocker.HasAssets));
        escrow.release(address(chog), 1, buyer);
        vault.withdrawERC20(address(usdc), 500e6, buyer);
        escrow.release(address(chog), 1, buyer);
        vm.stopPrank();
        assertEq(chog.ownerOf(1), buyer);
    }

    function test_zeroPrice_isAllowed() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(0, 1);
        _sell(a, _sign(a, buyerPk));
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
        assertEq(usdc.balanceOf(buyer), 1_000e6);
    }

    // ---- signatures
    function test_delegated7702Buyer_signsWithKey() external {
        vm.etch(buyer, hex"ef010063c0c19a282a1b52b07dd5a65b58948a07dae32b");
        AccountTransferCoordinator.Acceptance memory a = _acc(10e6, 1);
        _sell(a, _sign(a, buyerPk));
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
    }

    function test_erc1271SmartWalletBuyer() external {
        (address ownerAddr, uint256 ownerPk) = makeAddrAndKey("walletOwner");
        Wallet1271 w = new Wallet1271(ownerAddr);
        deal(address(usdc), address(w), 1_000e6);
        w.approveToken(usdc, address(coord), type(uint256).max);

        AccountTransferCoordinator.Acceptance memory a = _acc(50e6, 1);
        a.buyer = address(w);
        _sell(a, _sign(a, ownerPk));
        assertEq(escrow.beneficialOwnerOf(_key(1)), address(w));
        assertEq(usdc.balanceOf(seller), 50e6);
    }

    function test_wrongSigner_andTamperedTerms_rejected() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory good = _sign(a, buyerPk);
        (, uint256 otherPk) = makeAddrAndKey("other");
        bytes memory bad = _sign(a, otherPk);

        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(a, bad);

        AccountTransferCoordinator.Acceptance memory t = _clone(a);
        t.price = 1; // seller edits the price after the buyer signed
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(t, good);

        t = _clone(a);
        t.paymentToken = address(feeToken);
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(t, good);

        t = _clone(a);
        t.salt = 2;
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(t, good);

        t = _clone(a);
        t.stateNonce = a.stateNonce + 1;
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(t, good);

        assertEq(escrow.beneficialOwnerOf(_key(1)), seller);
        // and the untouched original still works
        _sell(a, good);
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
    }

    function test_signatureIsBoundToChainAndContract() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        vm.chainId(block.chainid + 1); // e.g. a chain fork or a different network
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.InvalidSignature.selector);
        coord.executeSale(a, sig);
    }

    function test_digestMatchesManualEip712() external view {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 7);
        bytes32 structHash = keccak256(
            abi.encode(
                coord.ACCEPTANCE_TYPEHASH(),
                a.key,
                a.seller,
                a.buyer,
                a.paymentToken,
                a.price,
                a.stateNonce,
                a.deadline,
                a.salt
            )
        );
        assertEq(coord.hashAcceptance(a), keccak256(abi.encodePacked("\x19\x01", coord.domainSeparator(), structHash)));
    }

    // ---- conditions
    function test_expired_replayed_cancelled() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(10e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        vm.warp(a.deadline + 1);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.Expired.selector, a.deadline));
        coord.executeSale(a, sig);
        vm.warp(a.deadline - 1 hours);

        // cancel by the buyer voids it
        vm.prank(bob);
        vm.expectRevert(AccountTransferCoordinator.NotBuyer.selector);
        coord.cancel(a);
        vm.prank(buyer);
        coord.cancel(a);
        bytes32 digest = coord.hashAcceptance(a);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.AlreadyUsed.selector, digest));
        coord.executeSale(a, sig);
    }

    function test_replayAfterOwnershipMovesOn_isRejected() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(10e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        _sell(a, sig);

        // the new owner sells on to carol
        (address carolAddr, uint256 carolPk) = makeAddrAndKey("carolKey");
        deal(address(usdc), carolAddr, 100e6);
        vm.prank(carolAddr);
        usdc.approve(address(coord), type(uint256).max);
        AccountTransferCoordinator.Acceptance memory next = _clone(a);
        next.seller = buyer;
        next.buyer = carolAddr;
        next.salt = 2;
        next.stateNonce = vault.stateNonce();
        bytes memory nextSig = _sign(next, carolPk);
        _sell(next, nextSig);
        assertEq(escrow.beneficialOwnerOf(_key(1)), carolAddr);

        // the first acceptance names alice as seller; she is no longer the beneficial owner
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.SellerNotBeneficialOwner.selector);
        coord.executeSale(a, sig);
    }

    function test_replayOfASpentAcceptance_isRejected_evenWhenEverythingElseIsValidAgain() external {
        // A key-controlled seller S sells to B, then B sells back to S. Every condition for replaying S's original
        // acceptance is now true again (S owns it, same state nonce, not expired, signature valid) except `used`.
        (address s, uint256 sPk) = makeAddrAndKey("keySeller");
        chog.mint(s, 3);
        vm.prank(s);
        registry.createAccount(address(chog), 3);
        vm.prank(s);
        chog.safeTransferFrom(s, address(escrow), 3);
        bytes32 key3 = _key(3);
        uint256 nonce3 = AccountVault(registry.vaultOf(address(chog), 3)).stateNonce();

        AccountTransferCoordinator.Acceptance memory first = AccountTransferCoordinator.Acceptance({
            key: key3,
            seller: s,
            buyer: buyer,
            paymentToken: address(usdc),
            price: 0,
            stateNonce: nonce3,
            deadline: block.timestamp + 7 days,
            salt: 1
        });
        bytes memory firstSig = _sign(first, buyerPk);
        vm.prank(s);
        coord.executeSale(first, firstSig);
        assertEq(escrow.beneficialOwnerOf(key3), buyer);

        AccountTransferCoordinator.Acceptance memory back = _clone(first);
        back.seller = buyer;
        back.buyer = s;
        back.salt = 2;
        bytes memory backSig = _sign(back, sPk);
        vm.prank(buyer);
        coord.executeSale(back, backSig);
        assertEq(escrow.beneficialOwnerOf(key3), s, "ownership is back with the original seller");

        bytes32 digest = coord.hashAcceptance(first);
        vm.prank(s);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.AlreadyUsed.selector, digest));
        coord.executeSale(first, firstSig);
    }

    function test_stateChangedAfterSigning_voidsTheAcceptance() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        // the seller empties part of the portfolio after the buyer looked at it
        vm.prank(seller);
        vault.withdrawERC20(address(usdc), 400e6, seller);
        uint256 nowNonce = vault.stateNonce();
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(AccountTransferCoordinator.StateChanged.selector, a.stateNonce, nowNonce)
        );
        coord.executeSale(a, sig);
        // and a deposit also changes the state
        assertEq(escrow.beneficialOwnerOf(_key(1)), seller);
    }

    function test_liabilitiesBlockTheSale() external {
        registry.bindCreditModule(address(module));
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory sig = _sign(a, buyerPk);

        module.setDebt(_key(1), 1);
        _expectHasLiabilities(a, sig, ReleaseBlocker.HasDebt);
        module.setDebt(_key(1), 0);
        module.setPending(_key(1), true);
        _expectHasLiabilities(a, sig, ReleaseBlocker.PendingOperation);
        module.setPending(_key(1), false);
        module.setBroken(true);
        _expectHasLiabilities(a, sig, ReleaseBlocker.ModuleUnavailable);
        module.setBroken(false);
        _sell(a, sig);
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
    }

    function _expectHasLiabilities(AccountTransferCoordinator.Acceptance memory a, bytes memory sig, ReleaseBlocker why)
        internal
    {
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.HasLiabilities.selector, why));
        coord.executeSale(a, sig);
    }

    function test_partiesAndAuthority() external {
        AccountTransferCoordinator.Acceptance memory a = _acc(1e6, 1);
        bytes memory sig = _sign(a, buyerPk);

        vm.prank(bob); // not the named seller
        vm.expectRevert(AccountTransferCoordinator.NotSeller.selector);
        coord.executeSale(a, sig);

        AccountTransferCoordinator.Acceptance memory s = _clone(a);
        s.seller = bob; // named seller is not the beneficial owner
        vm.prank(bob);
        vm.expectRevert(AccountTransferCoordinator.SellerNotBeneficialOwner.selector);
        coord.executeSale(s, sig);

        AccountTransferCoordinator.Acceptance memory self = _clone(a);
        self.buyer = seller;
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.BadParties.selector);
        coord.executeSale(self, sig);

        AccountTransferCoordinator.Acceptance memory zero = _clone(a);
        zero.buyer = address(0);
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.BadParties.selector);
        coord.executeSale(zero, sig);
    }

    function test_walletHeldAccountCannotBeSold() external {
        _openWalletHeld(alice, 2);
        AccountTransferCoordinator.Acceptance memory a = _acc(1e6, 1);
        a.key = _key(2);
        bytes memory sig = _sign(a, buyerPk);
        vm.prank(seller);
        vm.expectRevert(AccountTransferCoordinator.SellerNotBeneficialOwner.selector);
        coord.executeSale(a, sig);
    }

    // ---- payment failures roll everything back
    function test_paymentFailure_revertsWholeSale() external {
        vm.prank(buyer);
        usdc.approve(address(coord), 0);
        AccountTransferCoordinator.Acceptance memory a = _acc(100e6, 1);
        bytes memory sig = _sign(a, buyerPk);
        vm.prank(seller);
        vm.expectRevert();
        coord.executeSale(a, sig);
        assertEq(escrow.beneficialOwnerOf(_key(1)), seller, "ownership unchanged");
        assertFalse(coord.used(coord.hashAcceptance(a)), "acceptance not consumed");
    }

    function test_feeOnTransferPayment_rejected() external {
        feeToken.mint(buyer, 1_000e18);
        vm.prank(buyer);
        feeToken.approve(address(coord), type(uint256).max);
        AccountTransferCoordinator.Acceptance memory a = _acc(100e18, 1);
        a.paymentToken = address(feeToken);
        bytes memory sig = _sign(a, buyerPk);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(AccountTransferCoordinator.PaymentShortfall.selector, 100e18, 99e18));
        coord.executeSale(a, sig);
        assertEq(escrow.beneficialOwnerOf(_key(1)), seller);
    }

    function test_reentrantPaymentToken_cannotReenterCoordinator() external {
        ReentrantPayToken pay = new ReentrantPayToken();
        pay.mint(buyer, 1_000e18);
        vm.prank(buyer);
        pay.approve(address(coord), type(uint256).max);
        AccountTransferCoordinator.Acceptance memory a = _acc(100e18, 1);
        a.paymentToken = address(pay);
        bytes memory sig = _sign(a, buyerPk);
        // during the payment the token tries to execute the same sale again, as the coordinator itself would be called
        pay.arm(address(coord), abi.encodeCall(AccountTransferCoordinator.executeSale, (a, sig)));
        _sell(a, sig);
        assertTrue(pay.attempted());
        assertEq(bytes4(pay.failure()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
        assertEq(pay.balanceOf(seller), 100e18, "paid exactly once");
    }

    // ---- the escrow hook is not reachable by anyone else
    function test_escrowHook_onlyCoordinator() external {
        bytes32 key = _key(1);
        vm.prank(seller);
        vm.expectRevert(ChogCreditEscrow.NotCoordinator.selector);
        escrow.transferBeneficialOwnership(key, bob);
        vm.expectRevert(ChogCreditEscrow.NotCoordinator.selector);
        escrow.transferBeneficialOwnership(key, bob); // the test contract (also the registry binder) is not it either

        vm.startPrank(address(coord));
        vm.expectRevert(ChogCreditEscrow.ZeroAddress.selector);
        escrow.transferBeneficialOwnership(key, address(0));
        vm.expectRevert(abi.encodeWithSelector(ChogCreditEscrow.NotEscrowed.selector, bytes32(uint256(5))));
        escrow.transferBeneficialOwnership(bytes32(uint256(5)), bob);
        vm.stopPrank();
    }

    // ---- fuzz
    function testFuzz_saleConservesValue(uint96 price, uint256 salt) external {
        price = uint96(bound(price, 0, 1_000e6));
        AccountTransferCoordinator.Acceptance memory a = _acc(price, salt);
        uint256 totalBefore = usdc.balanceOf(seller) + usdc.balanceOf(buyer) + vault.accounted(address(usdc));
        _sell(a, _sign(a, buyerPk));
        assertEq(usdc.balanceOf(seller) + usdc.balanceOf(buyer) + vault.accounted(address(usdc)), totalBefore);
        assertEq(vault.accounted(address(usdc)), 500e6);
        assertEq(escrow.beneficialOwnerOf(_key(1)), buyer);
    }
}
