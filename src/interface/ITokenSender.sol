pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface ITokenSender {
    function sendToken(address token0, address token1, address pair, uint amount0, uint amount1) external;
}
