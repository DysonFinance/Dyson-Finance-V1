pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT
import "interface/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint) external;
}