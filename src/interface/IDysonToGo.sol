pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IDysonToGo {
    function ADDRESS_BOOK() external view returns (address);
    function WETH() external view returns (address);
    function DYSON() external view returns (address);
    function sDYSON() external view returns (address);
    function DYSON_FACTORY() external view returns (address);
    function DYSON_FARM() external view returns (address);
    function AgentNFT() external view returns (address);
    function Agency() external view returns (address);
    function CODE_HASH() external view returns (bytes32);
    function owner() external view returns (address);
    function adminFeeRatio() external view returns (uint);
    function spPool() external view returns (uint);
    function dysonPool() external view returns (uint);
    function spPending() external view returns (uint);
    function lastUpdateTime() external view returns (uint);
    function updatePeriod() external view returns (uint);
    function positionsCount(address pair, address user) external view returns (uint);
    function positions(address pair, address user, uint index) external view returns (uint, uint, bool);

    struct Position {
        uint index;
        uint spAmount;
        bool isWithdrawn;
    }

    event TransferOwnership(address newOwner);
    event Deposit(address indexed pair, address indexed user, uint index, uint spAmount);
    event Withdraw(address indexed pair, address indexed user, uint index, uint dysonAmount);
    event DYSONReceived(uint ownerAmount, uint poolAmount);

    function transferOwnership(address _owner) external;
    function rely(address tokenAddress, address contractAddress, bool enable) external;
    function relyDysonPair(address token, uint index, bool enable) external;
    function setAdminFeeRatio(uint ratio) external;
    function setUpdatePeriod(uint period) external;
    function gaugeDeposit(address gauge, uint amount) external;
    function gaugeApplyWithdrawal(address gauge, uint amount) external;
    function gaugeWithdraw(address gauge) external;
    function bribeClaimRewards(address gauge, address token, uint[] calldata week) external returns (uint amount);
    function adminWithdrawSdyson(uint amount) external ;
    function adminWithdrawAgent(uint tokenId) external;
    function update() external returns (uint sp);
    function deposit(address tokenIn, address tokenOut, uint index, uint input, uint minOutput, uint time) external returns (uint output);
    function depositETH(address tokenOut, uint index, uint minOutput, uint time) external payable returns (uint output);
    function withdraw(address pair, uint index, address to) external returns (uint token0Amt, uint token1Amt, uint dysonAmt);
    function withdrawETH(address pair, uint index, address to) external returns (uint token0Amt, uint token1Amt, uint dysonAmt);
    function swap(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput) external returns (uint output);
    function swapETHIn(address tokenOut, uint index, address to, uint minOutput) external payable returns (uint output);
    function swapETHOut(address tokenIn, uint index, address to, uint input, uint minOutput) external returns (uint output);
    function sign(bytes32 digest) external;
    function onERC721Received(address, address, uint, bytes calldata) external pure returns (bytes4);
}

interface IDysonToGoFactory {
    event TransferOwnership(address newOwner);
    event DysonToGoCreated(address dysonToGo);

    function ADDRESS_BOOK() external view returns (address);
    function WETH() external view returns (address);
    function owner() external view returns (address);
    function allInstances() external view returns (address[] memory);
    function allInstancesLength() external view returns (uint);
    function transferOwnership(address _owner) external;
    function createDysonToGo(address user) external returns (address dysonToGo);
}
