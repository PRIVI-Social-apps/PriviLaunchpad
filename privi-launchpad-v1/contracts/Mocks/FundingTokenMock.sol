// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice mock to simulate ERC20 funding tokens
 * @author Eric Nordelo
 */
contract FundingTokenMock is ERC20 {
    constructor() ERC20("Privi Funding Token Mock", "pFTM") {
        _mint(msg.sender, 10000000000 * 10**decimals());
    }
}
