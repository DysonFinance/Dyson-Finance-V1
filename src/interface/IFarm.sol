pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IFarm {
    event TransferOwnership(address newOwner);
    event RateUpdated(address indexed poolId, uint rewardRate, uint weight);
    event GrantSP(address indexed user, address indexed poolId, uint amountIn, uint amountOut);
    event Swap(address indexed user, address indexed parent, uint amountIn, uint amountOut);
    
    struct Pool {
        uint weight;
        uint rewardRate;
        uint lastUpdateTime;
        uint lastReserve;
        address gauge;
    }

    function agency() external view returns (address);
    function gov() external view returns (address);
    function owner() external view returns (address);
    function globalPool() external view returns (address);
    function pools(address poolId) external view returns (uint weight, uint rewardRate, uint lastUpdateTime, uint lastReserve, address gauge);
    function balanceOf(address user) external view returns (uint);
    function cooldown(address user) external view returns (uint);
    function transferOwnership(address _owner) external;
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function setPool(address poolId, address gauge) external;
    function setPoolRewardRate(address poolId, uint rewardRate, uint weight) external;
    function setGlobalRewardRate(uint rewardRate, uint weight) external;
    function getCurrentPoolReserve(address poolId) view external returns (uint reserve);
    function getCurrentGlobalReserve() view external returns (uint reserve);
    function grantSP(address to, uint amount) external;
    function swap(address user) external returns (uint amountOut);
}