// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ERC20 interface to allow withdraw to accounts
 * @author Eric Nordelo
 */
interface IWithdrawable {
    /**
     * @dev transfer the amount of selected tokens to address
     */
    function withdrawTo(
        address account,
        uint256 amount,
        address token
    ) external returns (bool);
}
