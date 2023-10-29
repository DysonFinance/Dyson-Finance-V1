pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IGaugeFactory {
    event GaugeCreated(address indexed poolId, address gauge);

    function controller() external returns (address);
    function pendingController() external returns (address);
    function permissionless() external returns (bool);
    function createGauge(address farm, address sgov, address poolId, uint weight, uint base, uint slope) external returns (address gauge);
    function setController(address _controller) external;
    function becomeController() external;
    function open2public() external;
}
