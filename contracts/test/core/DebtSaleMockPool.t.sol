// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoreBase, MockCreditModule} from "./CoreBase.sol";
import {AccountTransferCoordinator} from "../../src/core/AccountTransferCoordinator.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {IDebtSalePool} from "../../src/core/interfaces/IDebtSalePool.sol";

/// @notice TEST ONLY. A pool whose answers the test controls, to reach coordinator branches the real pool cannot
///         produce (a pending operation, a pool that pulls less than approved, state that changes during repay).
contract MockDebtPool is MockCreditModule, IDebtSalePool {
    IERC20 public immutable token;
    uint256 public collateralValue = 1_000e6;
    uint256 public healthBps = 20_000;
    bool public priceOk = true;
    bool public pullShort; // pull one unit less than approved
    bool public breakPriceOnRepay; // priceOk turns false during repay
    bool public breakHealthOnRepay; // health drops below 100% during repay

    constructor(IERC20 t) {
        token = t;
    }

    function set(uint256 collateral, uint256 health, bool ok) external {
        collateralValue = collateral;
        healthBps = health;
        priceOk = ok;
    }

    function setPullShort(bool v) external {
        pullShort = v;
    }

    function setBreakPriceOnRepay(bool v) external {
        breakPriceOnRepay = v;
    }

    function setBreakHealthOnRepay(bool v) external {
        breakHealthOnRepay = v;
    }

    function hasPendingOperation(bytes32 key) external view override(MockCreditModule, IDebtSalePool) returns (bool) {
        return pending[key];
    }

    function loanToken() external view returns (address) {
        return address(token);
    }

    function accountData(bytes32 key) external view returns (AccountData memory d) {
        d.priceOk = priceOk;
        d.debt = debt[key];
        d.collateralValue = collateralValue;
        d.healthFactorBps = debt[key] == 0 ? type(uint256).max : healthBps;
    }

    function repay(bytes32 key, uint256 amount) external returns (uint256) {
        token.transferFrom(msg.sender, address(this), pullShort ? amount - 1 : amount);
        debt[key] -= amount;
        if (breakPriceOnRepay) priceOk = false;
        if (breakHealthOnRepay) healthBps = 9_000;
        return amount;
    }
}

contract DebtSaleMockPoolTest is CoreBase {
    AccountTransferCoordinator internal coord;
    MockDebtPool internal pool;
    address internal buyer;
    uint256 internal buyerPk;
    bytes32 internal k;

    function setUp() public override {
        super.setUp();
        coord = AccountTransferCoordinator(escrow.coordinator());
        pool = new MockDebtPool(IERC20(address(usdc)));
        registry.bindCreditModule(address(pool));
        (buyer, buyerPk) = makeAddrAndKey("buyer");
        _open(alice, 1);
        k = _key(1);
        pool.setDebt(k, 300e6);
        deal(address(usdc), buyer, 1_000e6);
        vm.prank(buyer);
        usdc.approve(address(coord), type(uint256).max);
    }

    function _terms(uint256 price, uint256 repay)
        internal
        view
        returns (AccountTransferCoordinator.DebtAcceptance memory)
    {
        return AccountTransferCoordinator.DebtAcceptance({
            key: k,
            seller: alice,
            buyer: buyer,
            paymentToken: address(usdc),
            price: price,
            stateNonce: AccountVault(registry.accountInfo(k).vault).stateNonce(),
            epoch: escrow.epochOf(k),
            deadline: block.timestamp + 1 days,
            salt: 1,
            pool: address(pool),
            maxDebt: 1_000e6,
            minCollateralValue: 0,
            minHealthBps: 0,
            debtRepay: repay
        });
    }

    function _go(AccountTransferCoordinator.DebtAcceptance memory a, bytes memory err) internal {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPk, coord.hashDebtAcceptance(a));
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.prank(alice);
        if (err.length != 0) vm.expectRevert(err);
        coord.executeDebtSale(a, sig);
    }

    function test_pendingOperation_blocksTheSale() external {
        pool.setPending(k, true);
        _go(_terms(0, 0), abi.encodeWithSelector(AccountTransferCoordinator.PendingOperation.selector));
        assertEq(escrow.beneficialOwnerOf(k), alice);
    }

    function test_noLingeringApproval_evenIfThePoolPullsLess() external {
        pool.setPullShort(true);
        _go(_terms(100e6, 100e6), "");
        assertEq(usdc.allowance(address(coord), address(pool)), 0);
        assertEq(escrow.beneficialOwnerOf(k), buyer);
    }

    function test_successMarksTheDigestUsed() external {
        AccountTransferCoordinator.DebtAcceptance memory a = _terms(0, 0);
        bytes32 digest = coord.hashDebtAcceptance(a);
        _go(a, "");
        assertTrue(coord.used(digest));
    }

    function test_priceThatFailsDuringRepay_isCaughtAfterwards() external {
        pool.setBreakPriceOnRepay(true);
        _go(_terms(100e6, 100e6), abi.encodeWithSelector(AccountTransferCoordinator.PriceUnavailable.selector));
        assertEq(escrow.beneficialOwnerOf(k), alice);
    }

    function test_healthThatFallsDuringRepay_isCaughtAfterwards() external {
        pool.setBreakHealthOnRepay(true);
        _go(
            _terms(100e6, 100e6), abi.encodeWithSelector(AccountTransferCoordinator.AlreadyLiquidatable.selector, 9_000)
        );
        assertEq(escrow.beneficialOwnerOf(k), alice);
    }
}
