pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./Bribe.sol";

contract BribeFactory {
    address public controller;
    address public pendingController;
    bool public permissionless;

    event BribeCreated(address indexed gauge, address bribe);

    constructor(address _controller) {
        require(_controller != address(0), "controller cannot be zero");
        controller = _controller;
    }

    function createBribe(address gauge) external returns (address bribe) {
        require(permissionless || msg.sender == controller, "forbidden");
        bribe = address(new Bribe(gauge));
        emit BribeCreated(gauge, bribe);
    }

    function setController(address _controller) external {
        require(_controller != address(0), "controller cannot be zero");
        require(msg.sender == controller, "forbidden");
        pendingController = _controller;
    }

    function becomeController() external {
        require(msg.sender == pendingController, "forbidden");
        pendingController = address(0);
        controller = msg.sender;
    }

    function open2public() external {
        require(msg.sender == controller, "forbidden");
        permissionless = true;
    }
}
