pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IBribeFactory {
    event BribeCreated(address indexed gauge, address bribe);

    function controller() external returns (address);
    function pendingController() external returns (address);
    function permissionless() external returns (bool);
    function createBribe(address gauge) external returns (address bribe);
    function setController(address _controller) external;
    function becomeController() external;
    function open2public() external;
}
