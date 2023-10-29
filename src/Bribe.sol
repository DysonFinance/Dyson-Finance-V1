pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "interface/IGauge.sol";
import "./lib/TransferHelper.sol";

/// @title Contract for third parties to bribe sDYSON holders into
/// depositing their sDYSON in certain Gauge contract.
/// Each Bribe contract is paired with one Gauge contract.
/// Third parties can add multiple tokens as rewards.
contract Bribe {
    using TransferHelper for address;

    /// @notice Paired Gauge contract
    IGauge public gauge;

    /// @notice Record if user has claimed reward of given token from given week
    /// Param1 user User's address
    /// Param2 token Address of given token
    /// Param3 week i-th week since 1970/01/01
    mapping(address => mapping(address => mapping(uint => bool))) public claimed;
    /// @notice Record amount of given token allocated for given week
    /// Param1 token Address of given token
    /// Param2 week i-th week since 1970/01/01
    mapping(address => mapping(uint => uint)) public tokenRewardOfWeek;

    event AddReward(address indexed from, address indexed token, uint indexed week, uint amount);
    event ClaimReward(address indexed user, address indexed token, uint indexed week, uint amount);

    constructor(address _gauge) {
        gauge = IGauge(_gauge);
    }

    /// @notice Add reward of given token to given week.
    /// @param token Address of the token to add as reward
    /// @param week The week to add the reward to. It's the i-th week since 1970/01/01 and it must be the present week or a week in the future.
    /// @param amount Amount of token
    function addReward(address token, uint week, uint amount) external {
        require(week >= block.timestamp / 1 weeks, "cannot add for previous weeks");
        token.safeTransferFrom(msg.sender, address(this), amount);
        tokenRewardOfWeek[token][week] += amount;
        emit AddReward(msg.sender, token, week, amount);
    }

    function _claimReward(address token, uint week) internal returns (uint amount) {
        require(week < block.timestamp / 1 weeks, "not yet");
        require(!claimed[msg.sender][token][week], "claimed");
        uint userVotes = gauge.balanceOfAt(msg.sender, week);
        uint totalVotes = gauge.totalSupplyAt(week);
        amount = tokenRewardOfWeek[token][week] * userVotes / totalVotes;
        claimed[msg.sender][token][week] = true;
        emit ClaimReward(msg.sender, token, week, amount);
    }

    /// @notice Claim the reward by user
    /// @dev IMPORTANT: `totalSupply` in Gauge must be updated at least once a week.
    /// If `totalSupply` of a given week is not updated, user will not be able to claim the reward of the given week.
    /// @param token Address of the reward token
    /// @param week The week of the reward to claim. It's the i-th week since 1970/01/01 and it must be a week from the past.
    function claimReward(address token, uint week) external returns (uint amount) {
        amount = _claimReward(token, week);
        token.safeTransfer(msg.sender, amount);
    }

    function claimRewards(address token, uint[] calldata week) public returns (uint amount) {
        for(uint i = 0; i < week.length; ++i) {
            amount += _claimReward(token, week[i]);
        }
        token.safeTransfer(msg.sender, amount);
    }

    function claimRewardsMultipleTokens(address[] calldata token, uint[][] calldata week) external returns (uint[] memory amount) {
        amount = new uint[](token.length);
        for(uint i = 0; i < token.length; ++i) {
            amount[i] = claimRewards(token[i], week[i]);
        }
    }

}
