pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IGauge {
    event TransferOwnership(address newOwner);
    event Deposit(address indexed user, uint indexed week, uint amount);
    event ApplyWithdrawal(address indexed user, uint indexed week, uint amount);
    event Withdraw(address indexed user, uint amount);

    struct Checkpoint {
        uint week;
        uint amount;
    }

    function farm() external view returns (address);
    function SGOV() external view returns (address);
    function poolId() external view returns (address);
    function genesis() external view returns (uint);
    function weight() external view returns (uint);
    function totalSupply() external view returns (uint);
    function base() external view returns (uint);
    function slope() external view returns (uint);
    function thisWeek() external view returns (uint);
    function owner() external view returns (address);
    function numCheckpoints(address account) external view returns (uint);
    function checkpoints(address account, uint index) external view returns (uint week, uint amount);
    function pendingWithdrawal(address account) external view returns (uint);
    function weekToWithdraw(address account) external view returns (uint);
    function transferOwnership(address _owner) external;
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function setParams(uint _weight, uint _base, uint _slope) external;
    function balanceOf(address account) external view returns (uint);
    function balanceOfAt(address account, uint week) external view returns (uint);
    function totalSupplyAt(uint week) external view returns (uint);
    function tick() external;
    function nextRewardRate() external view returns (uint newRewardRate);
    function deposit(uint amount, address to) external;
    function applyWithdrawal(uint amount) external;
    function withdraw() external returns (uint amount);
    function bonus(address user) external view returns (uint _bonus);
}

    