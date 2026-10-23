// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The slice of the credit pool the transfer coordinator reads and calls for a debt-bearing sale.
///         Field order matches `ChogCreditPool.AccountData`.
interface IDebtSalePool {
    struct AccountData {
        bool priceOk;
        uint256 debt;
        uint256 collateralValue;
        uint256 borrowPower;
        uint256 liquidationValue;
        uint256 healthFactorBps;
        uint256 availableToBorrow;
    }

    function accountData(bytes32 key) external view returns (AccountData memory);
    function hasPendingOperation(bytes32 key) external view returns (bool);
    function loanToken() external view returns (address);
    function repay(bytes32 key, uint256 amount) external returns (uint256 repaid);
}
