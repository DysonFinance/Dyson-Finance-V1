pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IFactory {
    event PairCreated(address indexed token0, address indexed token1, uint id, address pair, uint);
    event GaugeCreated(address indexed poolId, address gauge);
    event BribeCreated(address indexed gauge, address bribe);

    function controller() external returns (address);
    function pendingController() external returns (address);
    function permissionless() external returns (bool);
    function getPairCount(address token0, address token1) external view returns (uint);
    function getPair(address token0, address token1, uint id) external view returns (address);
    function allPairs(uint id) external view returns (address);
    function allPairsLength() external view returns (uint);
    function getInitCodeHash() external pure returns (bytes32);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function createGauge(address farm, address sgov, address poolId, uint weight, uint base, uint slope) external returns (address gauge);
    function createBribe(address gauge) external returns (address bribe);
    function setController(address _controller) external;
    function becomeController() external;
    function open2public() external;
}