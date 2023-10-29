pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./Gauge.sol";

contract GaugeFactory {
    address public controller;
    address public pendingController;
    bool public permissionless;

    event GaugeCreated(address indexed poolId, address gauge);

    constructor(address _controller) {
        require(_controller != address(0), "controller cannot be zero");
        controller = _controller;
    }

    function createGauge(address farm, address sgov, address poolId, uint weight, uint base, uint slope) external returns (address gauge) {
        require(permissionless || msg.sender == controller, "forbidden");
        gauge = address(new Gauge(farm, sgov, poolId, weight, base, slope));
        Gauge(gauge).transferOwnership(controller);
        emit GaugeCreated(poolId, gauge);
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
