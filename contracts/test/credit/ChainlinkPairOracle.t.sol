// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ChainlinkPairOracle} from "../../src/credit/oracle/ChainlinkPairOracle.sol";
import {MockAggregator} from "../../src/mocks/MockOracles.sol";
import {TestToken} from "../../src/mocks/TestToken.sol";

contract ChainlinkPairOracleTest is Test {
    function mkOracle(address loan, ChainlinkPairOracle.FeedConfig[] memory c) external returns (ChainlinkPairOracle) {
        return new ChainlinkPairOracle(loan, c);
    }

    TestToken internal usdc; // loan token, 6 decimals
    TestToken internal wmon; // 18 decimals
    TestToken internal wbtc; // 8 decimals
    MockAggregator internal monA; // primary MON/USD, 8 decimals
    MockAggregator internal monB; // secondary MON/USD, 8 decimals
    MockAggregator internal usdcA; // USDC/USD, 8 decimals
    MockAggregator internal btcA; // BTC/USD, 18 decimals (unusual on purpose)
    ChainlinkPairOracle internal oracle;

    uint32 internal constant MAX_AGE = 1 hours;
    uint32 internal constant USDC_AGE = 25 hours;

    function setUp() external {
        vm.warp(1_700_000_000);
        usdc = new TestToken("USDC", "USDC", 6);
        wmon = new TestToken("WMON", "WMON", 18);
        wbtc = new TestToken("WBTC", "WBTC", 8);
        monA = new MockAggregator(8, 0.02e8); // $0.02
        monB = new MockAggregator(8, 0.02e8);
        usdcA = new MockAggregator(8, 1e8); // $1.00
        btcA = new MockAggregator(18, 60_000e18);
        oracle = _build(address(monB));
    }

    function _cfg(address token, address primary, address secondary, uint32 age, uint16 dev)
        internal
        pure
        returns (ChainlinkPairOracle.FeedConfig memory)
    {
        return ChainlinkPairOracle.FeedConfig(token, primary, secondary, age, dev);
    }

    function _build(address monSecondary) internal returns (ChainlinkPairOracle) {
        ChainlinkPairOracle.FeedConfig[] memory c = new ChainlinkPairOracle.FeedConfig[](3);
        c[0] = _cfg(address(usdc), address(usdcA), address(0), USDC_AGE, 0);
        c[1] = _cfg(address(wmon), address(monA), monSecondary, MAX_AGE, 300);
        c[2] = _cfg(address(wbtc), address(btcA), address(0), MAX_AGE, 0);
        return new ChainlinkPairOracle(address(usdc), c);
    }

    // ---- pricing
    function test_basicQuote_wmonInUsdc() external view {
        assertEq(oracle.quote(address(wmon), 100e18), 2e6); // 100 WMON at $0.02 = $2 = 2 USDC
        assertEq(oracle.quote(address(wmon), 0), 0);
        assertEq(oracle.quote(address(usdc), 5e6), 5e6, "the loan token is worth itself");
    }

    function test_quote_handlesMixedDecimals() external view {
        // 0.5 BTC at $60,000 = $30,000 = 30,000 USDC (8-decimal token, 18-decimal feed)
        assertEq(oracle.quote(address(wbtc), 0.5e8), 30_000e6);
    }

    function test_loanTokenDepeg_isReflectedInCollateralValue() external {
        usdcA.set(0.98e8, block.timestamp); // USDC trades at $0.98
        // $2 of WMON is worth 2 / 0.98 USDC
        assertEq(oracle.quote(address(wmon), 100e18), Math.mulDiv(2e6, 1e8, 0.98e8));
        usdcA.set(1.02e8, block.timestamp);
        assertEq(oracle.quote(address(wmon), 100e18), Math.mulDiv(2e6, 1e8, 1.02e8));
    }

    function test_twoSources_lowerPriceIsUsed() external {
        monA.set(0.0205e8, block.timestamp);
        monB.set(0.02e8, block.timestamp);
        assertEq(oracle.quote(address(wmon), 100e18), 2e6);
        monA.set(0.02e8, block.timestamp);
        monB.set(0.0204e8, block.timestamp);
        assertEq(oracle.quote(address(wmon), 100e18), 2e6);
    }

    function test_twoSources_deviationBeyondBoundReverts() external {
        monA.set(0.02e8, block.timestamp);
        monB.set(0.0207e8, block.timestamp); // 3.5% apart, bound is 3%
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPairOracle.FeedDeviation.selector, 0.02e18, 0.0207e18));
        oracle.quote(address(wmon), 1e18);
        monB.set(0.0206e8, block.timestamp); // exactly 3%: allowed
        oracle.quote(address(wmon), 1e18);
    }

    // ---- failure modes: all revert, never return a number
    function test_staleFeed_reverts_perFeedAge() external {
        vm.warp(block.timestamp + MAX_AGE + 1);
        usdcA.set(1e8, block.timestamp); // keep the loan feed fresh
        monB.set(0.02e8, block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPairOracle.StalePrice.selector, address(monA), block.timestamp - MAX_AGE - 1
            )
        );
        oracle.quote(address(wmon), 1e18);
    }

    function test_secondaryStale_alsoReverts() external {
        vm.warp(block.timestamp + MAX_AGE + 1);
        monA.set(0.02e8, block.timestamp);
        usdcA.set(1e8, block.timestamp);
        vm.expectRevert();
        oracle.quote(address(wmon), 1e18);
    }

    function test_loanFeedStale_blocksEverything_butHasItsOwnLongerAge() external {
        vm.warp(block.timestamp + 10 hours);
        monA.set(0.02e8, block.timestamp);
        monB.set(0.02e8, block.timestamp);
        oracle.quote(address(wmon), 1e18); // USDC feed is 10h old but allowed 25h
        vm.warp(block.timestamp + 16 hours);
        monA.set(0.02e8, block.timestamp);
        monB.set(0.02e8, block.timestamp);
        vm.expectRevert();
        oracle.quote(address(wmon), 1e18); // now 26h old
    }

    function test_nonPositiveAndZeroPrices_revert() external {
        monA.set(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPairOracle.InvalidPrice.selector, address(monA)));
        oracle.quote(address(wmon), 1e18);
        monA.set(-5, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPairOracle.InvalidPrice.selector, address(monA)));
        oracle.quote(address(wmon), 1e18);
        monA.set(0.02e8, block.timestamp);
        usdcA.set(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPairOracle.InvalidPrice.selector, address(usdcA)));
        oracle.quote(address(wmon), 1e18);
    }

    function test_futureTimestampAndZeroTimestamp_revert() external {
        monA.set(0.02e8, block.timestamp + 1);
        vm.expectRevert();
        oracle.quote(address(wmon), 1e18);
        monA.set(0.02e8, 0);
        vm.expectRevert();
        oracle.quote(address(wmon), 1e18);
    }

    function test_revertingFeed_reverts() external {
        monB.setReverts(true);
        vm.expectRevert();
        oracle.quote(address(wmon), 1e18);
    }

    function test_unknownToken_reverts() external {
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPairOracle.UnknownToken.selector, address(0xdead)));
        oracle.quote(address(0xdead), 1);
    }

    // ---- construction
    function test_constructorValidation() external {
        ChainlinkPairOracle.FeedConfig[] memory c = new ChainlinkPairOracle.FeedConfig[](1);
        c[0] = _cfg(address(wmon), address(monA), address(0), MAX_AGE, 0);
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector); // no feed for the loan token
        this.mkOracle(address(usdc), c);

        c = new ChainlinkPairOracle.FeedConfig[](2);
        c[0] = _cfg(address(usdc), address(usdcA), address(0), USDC_AGE, 0);
        c[1] = _cfg(address(usdc), address(usdcA), address(0), USDC_AGE, 0); // duplicate
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector);
        this.mkOracle(address(usdc), c);

        c[1] = _cfg(address(wmon), address(monA), address(0), 0, 0); // zero max age
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector);
        this.mkOracle(address(usdc), c);
        c[1] = _cfg(address(wmon), address(monA), address(monB), MAX_AGE, 0); // secondary without a bound
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector);
        this.mkOracle(address(usdc), c);
        c[1] = _cfg(address(wmon), address(monA), address(monB), MAX_AGE, 2_001); // bound too loose
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector);
        this.mkOracle(address(usdc), c);
        c[1] = _cfg(address(wmon), address(0), address(0), MAX_AGE, 0);
        vm.expectRevert(ChainlinkPairOracle.ZeroAddress.selector);
        this.mkOracle(address(usdc), c);

        c[1] = _cfg(address(wmon), address(monA), address(0), MAX_AGE, 0);
        vm.expectRevert(ChainlinkPairOracle.ZeroAddress.selector); // zero loan token
        this.mkOracle(address(0), c);

        TestToken huge = new TestToken("Huge", "HUGE", 37);
        c[1] = _cfg(address(huge), address(monA), address(0), MAX_AGE, 0);
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector); // token with more than 36 decimals
        this.mkOracle(address(usdc), c);

        MockAggregator weird = new MockAggregator(19, 1);
        c[1] = _cfg(address(wmon), address(weird), address(0), MAX_AGE, 0); // > 18 decimals
        vm.expectRevert(ChainlinkPairOracle.BadConfig.selector);
        this.mkOracle(address(usdc), c);
    }

    function test_noSettersExist() external {
        (bool ok,) =
            address(oracle).call(abi.encodeWithSignature("setFeed(address,address)", address(wmon), address(0)));
        assertFalse(ok);
        (ok,) = address(oracle).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
    }

    // ---- properties
    function testFuzz_quoteMatchesReferenceAndNeverOverstates(uint128 amount, uint64 monPrice, uint64 usdcPrice)
        external
    {
        monPrice = uint64(bound(monPrice, 1e4, 1e12)); // $0.0001 .. $10,000 (8 decimals)
        usdcPrice = uint64(bound(usdcPrice, 0.5e8, 1.5e8));
        monA.set(int256(uint256(monPrice)), block.timestamp);
        monB.set(int256(uint256(monPrice)), block.timestamp);
        usdcA.set(int256(uint256(usdcPrice)), block.timestamp);
        uint256 got = oracle.quote(address(wmon), amount);
        // exact reference with 512-bit math: amount * monPrice * 1e6 / (1e18 * usdcPrice)
        uint256 want = Math.mulDiv(uint256(amount), uint256(monPrice) * 1e6, 1e18 * uint256(usdcPrice));
        assertEq(got, want);
    }

    function testFuzz_quoteIsMonotonicInAmount(uint96 a, uint96 b) external view {
        (uint96 lo, uint96 hi) = a < b ? (a, b) : (b, a);
        assertLe(oracle.quote(address(wmon), lo), oracle.quote(address(wmon), hi));
    }

    function test_hugeAmountDoesNotOverflow() external view {
        assertGt(oracle.quote(address(wmon), 1e36), 0);
    }
}
