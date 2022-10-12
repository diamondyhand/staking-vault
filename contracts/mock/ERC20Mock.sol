// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract ERC20Mock is ERC20 {
    constructor() ERC20('MockERC20', 'MCK') {}

    /// @dev Give free tokens to anyone
    function mint(address receiver, uint256 value) external {
        _mint(receiver, value);
    }
}
