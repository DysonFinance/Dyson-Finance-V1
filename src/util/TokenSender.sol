pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "interface/IERC20.sol";

contract TokenSender {
    function sendToken(address token0, address token1, address pair, uint amount0, uint amount1) external {
        IERC20(token0).transferFrom(msg.sender, pair, amount0);
        IERC20(token1).transferFrom(msg.sender, pair, amount1);
    }
}
