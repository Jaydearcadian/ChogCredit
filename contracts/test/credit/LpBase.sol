// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CreditBase} from "./CreditBase.sol";
import {AccountVault} from "../../src/core/AccountVault.sol";
import {ChogCreditPool} from "../../src/credit/ChogCreditPool.sol";
import {LpMath} from "../../src/credit/lib/LpMath.sol";
import {MockV3Factory, MockV3Pool, MockPositionManager} from "../../src/mocks/MockUniswapV3.sol";

/// @dev The credit system with one whitelisted Uniswap V3 pool (WMON/USDC 0.30%) behind a mock position manager.
///      The oracle prices WMON at 2 USDC and USDC at 1; one full-range position of liquidity `L_2K` holds about
///      2,000 USDC of value. LP parameters: LTV 35%, threshold 52.5%, bonus 5%, 2% price-gap bound, 50,000 USDC cap.
abstract contract LpBase is CreditBase {
    MockV3Factory public v3f;
    MockPositionManager public pm;
    MockV3Pool public lpPool;

    int24 internal constant FULL_LO = -887220;
    int24 internal constant FULL_HI = 887220;
    uint128 public constant L_2K = 707_106_781_186_548;

    function _lpConfig() internal virtual override returns (ChogCreditPool.LpConfig memory lp) {
        oracle.setPrice(address(usdc), 1e6);
        v3f = new MockV3Factory();
        pm = new MockPositionManager(address(v3f));
        lpPool = MockV3Pool(v3f.createPool(address(wmon), address(usdc), 3000));
        lp.positionManager = address(pm);
        lp.pools = new ChogCreditPool.LpPoolConfig[](1);
        lp.pools[0] = ChogCreditPool.LpPoolConfig(address(lpPool), 3_500, 5_250, 500, 200, 50_000 * USDC);
    }

    function setUp() public virtual override {
        super.setUp();
        deal(address(usdc), address(pm), 1e18);
        wmon.mint(address(pm), 1e36);
        _syncPoolPrice();
    }

    // ---- price helpers
    function _oracleSqrt() internal view returns (uint160) {
        address t0 = lpPool.token0();
        address t1 = lpPool.token1();
        uint256 s0 = 10 ** IERC20Metadata(t0).decimals() * 1e6;
        uint256 s1 = 10 ** IERC20Metadata(t1).decimals() * 1e6;
        return LpMath.sqrtPriceFromValues(oracle.quote(t0, s0), s0, oracle.quote(t1, s1), s1);
    }

    /// @dev Public so handlers can move the pool with the oracle.
    function syncPoolPrice() public {
        _syncPoolPrice();
    }

    function _syncPoolPrice() internal {
        lpPool.setSqrtPrice(_oracleSqrt());
    }

    /// @dev Move the oracle price of WMON (loan-token raw units per whole WMON) and the pool with it.
    function _setWmonPrice(uint256 priceRaw) internal {
        oracle.setPrice(address(wmon), priceRaw);
        _syncPoolPrice();
    }

    /// @dev Largest tick whose price is at or below `sqrtP`, rounded down to the 60 spacing.
    function _tickAtOrBelow(uint160 sqrtP) internal pure returns (int24) {
        int24 lo = -887_220;
        int24 hi = 887_220;
        while (lo < hi) {
            int24 mid = lo + (hi - lo + 1) / 2;
            if (LpMath.sqrtRatioAtTick(mid) <= sqrtP) lo = mid;
            else hi = mid - 1;
        }
        return (lo / 60) * 60;
    }

    // ---- actions
    function _openAccount(address who, uint256 id) internal returns (AccountVault v) {
        vm.startPrank(who);
        v = AccountVault(registry.createAccount(address(chog), id));
        chog.safeTransferFrom(who, address(escrow), id);
        vm.stopPrank();
    }

    function _mint(address owner, uint128 liquidity) internal returns (uint256) {
        return pm.mint(owner, address(lpPool), FULL_LO, FULL_HI, liquidity);
    }

    function _depositPos(address who, uint256 id, uint256 tokenId) internal {
        AccountVault v = AccountVault(registry.vaultOf(address(chog), id));
        vm.startPrank(who);
        pm.approve(address(v), tokenId);
        v.depositPosition(tokenId);
        vm.stopPrank();
    }

    /// @dev Open Chog `id` for `who` with one full-range position of `liquidity`; returns the position id.
    function _openWithPosition(address who, uint256 id, uint128 liquidity) internal returns (uint256 tokenId) {
        _openAccount(who, id);
        tokenId = _mint(who, liquidity);
        _depositPos(who, id, tokenId);
    }
}
