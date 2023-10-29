pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IPair {
    event Swap(address indexed sender, bool indexed isSwap0, uint amountIn, uint amountOut, address indexed to);
    event FeeCollected(uint token0Amt, uint token1Amt);
    event Deposit(address indexed user, bool indexed isToken0, uint index, uint amountIn, uint token0Amt, uint token1Amt, uint due);
    event Withdraw(address indexed user, bool indexed isToken0, uint index, uint amountOut);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    struct Note {
        uint token0Amt;
        uint token1Amt;
        uint due;
    }

    function token0() external view returns (address);
    function token1() external view returns (address);
    function getFeeRatio() external view returns(uint64 _feeRatio0, uint64 _feeRatio1);
    function getReserves() external view returns (uint reserve0, uint reserve1);
    function deposit0(address to, uint input, uint minOutput, uint time) external returns (uint output);
    function deposit1(address to, uint input, uint minOutput, uint time) external returns (uint output);
    function swap0in(address to, uint input, uint minOutput) external returns (uint output);
    function swap1in(address to, uint input, uint minOutput) external returns (uint output);
    function withdraw(uint index, address to) external returns (uint token0Amt, uint token1Amt);
    function halfLife() external view returns (uint64);
    function calcNewFeeRatio(uint64 _oldFeeRatio, uint _elapsedTime) external view returns (uint64 _newFeeRatio);
    function feeTo() external view returns (address);
    function initialize(address _token0, address _token1) external;
    function collectFee() external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function WITHDRAW_TYPEHASH() external pure returns (bytes32);
    function factory() external view returns (address);
    function farm() external view returns (address);
    function basis() external view returns (uint);
    function noteCount(address user) external view returns (uint);
    function notes(address user, uint index) external view returns (Note memory);
    function getPremium(uint time) external view returns (uint premium);
    function setBasis(uint _basis) external;
    function setHalfLife(uint64 _halfLife) external;
    function setFarm(address _farm) external;
    function setFeeTo(address _feeTo) external;
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function setApprovalForAllWithSig(address owner, address operator, bool approved, uint deadline, bytes calldata sig) external;
    function setApprovalForAll(address operator, bool approved) external;
    function operatorApprovals(address owner, address operator) external view returns (bool);
    function withdrawFrom(address from, uint index, address to) external returns (uint token0Amts, uint token1Amts);
}