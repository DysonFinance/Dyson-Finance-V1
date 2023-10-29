pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

import "./IERC20.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint amount) external returns (bool);
}