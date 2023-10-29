pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

interface IBribe {
    event AddReward(address indexed from, address indexed token, uint indexed week, uint amount);
    event ClaimReward(address indexed user, address indexed token, uint indexed week, uint amount);

    function gauge() external view returns (address);
    function claimed(address user, address token, uint week) external view returns (bool);
    function tokenRewardOfWeek(address token, uint week) external view returns (uint);
    function addReward(address token, uint week, uint amount) external;
    function claimReward(address token, uint week) external returns (uint amount);
    function claimRewards(address token, uint[] calldata week) external returns (uint amount);
    function claimRewardsMultipleTokens(address[] calldata token, uint[][] calldata week) external returns (uint[] memory amount);
}
