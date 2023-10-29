pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./Pair.sol";

contract Factory {
    address public controller;
    address public pendingController;
    bool public permissionless;

    mapping(address => mapping(address => uint)) public getPairCount;
    mapping(address => mapping(address => mapping(uint => address))) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, uint id, address pair);

    constructor(address _controller) {
        require(_controller != address(0), "controller cannot be zero");
        controller = _controller;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function getInitCodeHash() external pure returns (bytes32) {
        return keccak256(type(Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(permissionless || msg.sender == controller, "forbidden");
        require(tokenA != tokenB, "identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "zero address");
        uint id = ++getPairCount[token0][token1];
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, id));
        pair = address(new Pair{salt : salt}());
        Pair(pair).initialize(token0, token1);
        getPair[token0][token1][id - 1] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, id, pair);
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
