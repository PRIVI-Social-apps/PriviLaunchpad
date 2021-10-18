// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice mock to simulate app token contract
 * @author Eric Nordelo
 */
contract AppTokenMock is ERC20 {
    constructor() ERC20("App Token Mock", "pATM") {
        _mint(msg.sender, 10000000000 * 10**decimals());
    }
}
