// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ChogAccountRegistry} from "../core/ChogAccountRegistry.sol";
import {ChogCreditPool} from "./ChogCreditPool.sol";

/// @title ChogCreditFactory
/// @notice Deploys the registry and the pool and binds the pool as the registry's credit module in ONE transaction
///         (its constructor). The factory is the registry's binder; after the constructor that power is spent, and the
///         factory has no other function. This removes the "deployer may bind any module later" trust assumption.
contract ChogCreditFactory {
    struct Params {
        address[] collections; // allowlisted Chog collections
        address[] extraTokens; // additional vault-allowed tokens (collateral tokens are added automatically)
        address rescuer; // address(0) disables stranded-token rescue
        ChogCreditPool.PoolConfig pool;
        ChogCreditPool.CollateralConfig[] collaterals;
        ChogCreditPool.LpConfig lp; // positionManager == address(0) disables LP positions
    }

    ChogAccountRegistry public immutable registry;
    ChogCreditPool public immutable pool;

    event Deployed(address indexed registry, address indexed pool, address indexed escrow, address coordinator);

    constructor(Params memory p) {
        // With LP positions the loan token must be vault-allowed too: an unwound position pays out in it.
        bool addLoan = p.lp.positionManager != address(0) && !_listed(p, p.pool.loanToken);
        address[] memory tokens = new address[](p.collaterals.length + p.extraTokens.length + (addLoan ? 1 : 0));
        for (uint256 i; i < p.collaterals.length; ++i) {
            tokens[i] = p.collaterals[i].token;
        }
        for (uint256 i; i < p.extraTokens.length; ++i) {
            tokens[p.collaterals.length + i] = p.extraTokens[i];
        }
        if (addLoan) tokens[tokens.length - 1] = p.pool.loanToken;
        ChogAccountRegistry r = new ChogAccountRegistry(p.collections, tokens, address(this), p.rescuer);
        ChogCreditPool pl = new ChogCreditPool(address(r), p.pool, p.collaterals, p.lp);
        r.bindCreditModule(address(pl));
        registry = r;
        pool = pl;
        emit Deployed(address(r), address(pl), address(r.escrow()), r.escrow().coordinator());
    }

    function _listed(Params memory p, address token) private pure returns (bool) {
        for (uint256 i; i < p.collaterals.length; ++i) {
            if (p.collaterals[i].token == token) return true;
        }
        for (uint256 i; i < p.extraTokens.length; ++i) {
            if (p.extraTokens[i] == token) return true;
        }
        return false;
    }
}
