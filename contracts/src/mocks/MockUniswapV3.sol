// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../credit/interfaces/IUniswapV3.sol";
import {LpMath} from "../credit/lib/LpMath.sol";

/// @notice TEST / TESTNET ONLY. Just enough of a Uniswap V3 pool for the credit pool: tokens, fee and a settable price.
contract MockV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    uint160 public sqrtPriceX96;
    bool public reverts;

    constructor(address a, address b, uint24 fee_) {
        (token0, token1) = a < b ? (a, b) : (b, a);
        fee = fee_;
        sqrtPriceX96 = uint160(1 << 96);
    }

    function setSqrtPrice(uint160 p) external {
        sqrtPriceX96 = p;
    }

    function setReverts(bool r) external {
        reverts = r;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        require(!reverts, "pool down");
        return (sqrtPriceX96, 0, 0, 0, 0, 0, true);
    }
}

contract MockV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function createPool(address a, address b, uint24 fee) external returns (address pool) {
        pool = address(new MockV3Pool(a, b, fee));
        getPool[a][b][fee] = pool;
        getPool[b][a][fee] = pool;
    }
}

/// @notice TEST / TESTNET ONLY. A position manager with real liquidity maths: removing liquidity pays the amounts the
///         position holds at the mock pool's current price. Holds the tokens itself, so tests fund it with `deal`.
///         `transferFrom` follows ERC-721 rules (owner, approved, or operator); it never calls a receiver.
contract MockPositionManager {
    struct Pos {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 owed0;
        uint128 owed1;
        address operator;
        bool exists;
    }

    address public immutable factory;
    uint256 public nextId = 1;
    mapping(uint256 => Pos) internal _pos;
    mapping(uint256 => address) internal _owner;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    bool public shortReply; // positions() answers with a single word
    bool public transferIsNoop; // transferFrom succeeds without moving the token

    constructor(address factory_) {
        factory = factory_;
    }

    // ---------------------------------------------------------------- test hooks

    function mint(address to, address pool, int24 tl, int24 tu, uint128 liquidity) external returns (uint256 id) {
        id = nextId++;
        MockV3Pool p = MockV3Pool(pool);
        _pos[id] = Pos(p.token0(), p.token1(), p.fee(), tl, tu, liquidity, 0, 0, address(0), true);
        _owner[id] = to;
    }

    function addFees(uint256 id, uint128 a0, uint128 a1) external {
        _pos[id].owed0 += a0;
        _pos[id].owed1 += a1;
    }

    function setShortReply(bool v) external {
        shortReply = v;
    }

    function setTransferIsNoop(bool v) external {
        transferIsNoop = v;
    }

    function burnForTest(uint256 id) external {
        delete _pos[id];
        delete _owner[id];
    }

    function setLiquidityForTest(uint256 id, uint128 liquidity) external {
        _pos[id].liquidity = liquidity;
    }

    // ---------------------------------------------------------------- ERC-721 subset

    function ownerOf(uint256 id) public view returns (address o) {
        o = _owner[id];
        require(o != address(0), "Invalid token ID");
    }

    /// @dev ERC721Enumerable subset the real NonfungiblePositionManager has, so the app lists positions the same way.
    ///      Linear scans: fine for a mock.
    function balanceOf(address who) public view returns (uint256 n) {
        for (uint256 i = 1; i < nextId; i++) {
            if (_owner[i] == who) ++n;
        }
    }

    function tokenOfOwnerByIndex(address who, uint256 index) external view returns (uint256) {
        uint256 seen;
        for (uint256 i = 1; i < nextId; i++) {
            if (_owner[i] == who) {
                if (seen == index) return i;
                ++seen;
            }
        }
        revert("index out of bounds");
    }

    function approve(address spender, uint256 id) external {
        address o = ownerOf(id);
        require(msg.sender == o || isApprovedForAll[o][msg.sender], "not owner");
        _pos[id].operator = spender;
    }

    function setApprovalForAll(address operator, bool ok) external {
        isApprovedForAll[msg.sender][operator] = ok;
    }

    function _isApprovedOrOwner(address who, uint256 id) internal view returns (bool) {
        address o = ownerOf(id);
        return who == o || _pos[id].operator == who || isApprovedForAll[o][who];
    }

    function transferFrom(address from, address to, uint256 id) external {
        require(_isApprovedOrOwner(msg.sender, id), "not approved");
        require(ownerOf(id) == from, "wrong from");
        require(to != address(0), "zero to");
        if (transferIsNoop) return;
        _owner[id] = to;
        _pos[id].operator = address(0);
    }

    // ---------------------------------------------------------------- positions

    function positions(uint256 id)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 g0,
            uint256 g1,
            uint128 owed0,
            uint128 owed1
        )
    {
        if (shortReply) {
            assembly {
                mstore(0x00, 1)
                return(0x00, 0x20)
            }
        }
        Pos storage p = _pos[id];
        require(p.exists, "Invalid token ID");
        return (0, p.operator, p.token0, p.token1, p.fee, p.tickLower, p.tickUpper, p.liquidity, 0, 0, p.owed0, p.owed1);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external returns (uint256 a0, uint256 a1) {
        require(_isApprovedOrOwner(msg.sender, params.tokenId), "not approved");
        Pos storage p = _pos[params.tokenId];
        require(params.liquidity <= p.liquidity, "too much");
        address pool = MockV3Factory(factory).getPool(p.token0, p.token1, p.fee);
        (uint160 sqrtP,,,,,,) = MockV3Pool(pool).slot0();
        (a0, a1) = LpMath.amountsForLiquidity(
            sqrtP, LpMath.sqrtRatioAtTick(p.tickLower), LpMath.sqrtRatioAtTick(p.tickUpper), params.liquidity
        );
        p.liquidity -= params.liquidity;
        p.owed0 += uint128(a0);
        p.owed1 += uint128(a1);
    }

    function collect(CollectParams calldata params) external returns (uint256 a0, uint256 a1) {
        require(_isApprovedOrOwner(msg.sender, params.tokenId), "not approved");
        Pos storage p = _pos[params.tokenId];
        address to = params.recipient == address(0) ? address(this) : params.recipient;
        a0 = p.owed0 < params.amount0Max ? p.owed0 : params.amount0Max;
        a1 = p.owed1 < params.amount1Max ? p.owed1 : params.amount1Max;
        p.owed0 -= uint128(a0);
        p.owed1 -= uint128(a1);
        if (a0 != 0) IERC20(p.token0).transfer(to, a0);
        if (a1 != 0) IERC20(p.token1).transfer(to, a1);
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
}
