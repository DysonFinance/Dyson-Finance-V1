pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "interface/IAgency.sol";
import "interface/IERC20Mintable.sol";
import "interface/IGauge.sol";
import "./lib/ABDKMath64x64.sol";
import "./lib/TransferHelper.sol";

/// @title Contract for Dyson user to earn extra rewards.
/// A Pair and a Gauge contract together form a pool.
/// This contract will record reward related info about each pools.
/// Each Pair will trigger `Farm.grantSP` upon user deposit,
/// it will add to user's SP balance.
/// User can call `Farm.swap` to swap SP token to gov token, i.e., DYSON token.
contract Farm {
    using ABDKMath64x64 for *;
    using TransferHelper for address;

    int128 private constant MAX_AP_RATIO = 2**64;
    uint private constant BONUS_BASE_UNIT = 1e18;
    /// @notice Cooldown before user can swap his SP to gov token
    uint private constant CD = 6000;
    IAgency public immutable agency;
    /// @notice Governance token, i.e., DYSON token
    IERC20Mintable public immutable gov;

    address public owner;

    /// @member weight A parameter in the exchange formula when converting localSP to globalSP or converting globalSP to DYSON.
    /// The higher the weight, the lower the reward
    /// @member rewardRate Pool reward rate. The higher the rate, the faster the reserve grows
    /// @member lastUpdateTime Last time the pool reserve is updated
    /// @member lastReserve The pool reserve amount when last updated
    /// @member gauge Gauge contract of the pool which records the pool's weight and rewardRate
    struct Pool {
        uint weight;
        uint rewardRate;
        uint lastUpdateTime;
        uint lastReserve;
        address gauge;
    }

    /// @notice The special pool for gov token
    Pool public globalPool;

    /// Param poolId Id of the pool. Note that pool id is the address of Pair contract
    mapping(address => Pool) public pools;
    /// @notice User's SP balance
    mapping(address => uint) public balanceOf;
    /// @notice Timestamp when user's cooldown ends
    mapping(address => uint) public cooldown;

    event TransferOwnership(address newOwner);
    event RateUpdated(address indexed poolId, uint rewardRate, uint weight);
    event GrantSP(address indexed user, address indexed poolId, uint amountIn, uint amountOut);
    event Swap(address indexed user, address indexed parent, uint amountIn, uint amountOut);

    constructor(address _owner, address _agency, address _gov) {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;
        agency = IAgency(_agency);
        gov = IERC20Mintable(_gov);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) onlyOwner external {
        tokenAddress.safeTransfer(to, amount);
    }

    /// @dev Set the Gauge contract for given pool
    /// @param poolId Pool Id, i.e., address of the Pair contract
    /// @param gauge address of the Gauge contract
    function setPool(address poolId, address gauge) external onlyOwner {
        Pool storage pool = pools[poolId];
        pool.gauge = gauge;
        pool.lastReserve = getCurrentPoolReserve(poolId);
        pool.lastUpdateTime = block.timestamp;
        pool.rewardRate = IGauge(gauge).nextRewardRate();
        pool.weight = IGauge(gauge).weight();
        emit RateUpdated(poolId, pool.rewardRate, pool.weight);
    }

    /// @dev Update given pool's `weight` and `rewardRate`, triggered by the pool's Gauge contract
    /// @param poolId Pool Id, i.e., address of the Pair contract
    /// @param rewardRate New `rewardRate`
    /// @param weight New `weight`
    function setPoolRewardRate(address poolId, uint rewardRate, uint weight) external {
        Pool storage pool = pools[poolId];
        require(pool.gauge == msg.sender, "not gauge");
        pool.lastReserve = getCurrentPoolReserve(poolId);
        pool.lastUpdateTime = block.timestamp;
        pool.rewardRate = rewardRate;
        pool.weight = weight;
        emit RateUpdated(poolId, rewardRate, weight);
    }

    /// @notice Update gov token pool's `rewardRate` and `weight`
    /// @param rewardRate New `rewardRate`
    /// @param weight New `weight`
    function setGlobalRewardRate(uint rewardRate, uint weight) external onlyOwner {
        globalPool.lastReserve = getCurrentGlobalReserve();
        globalPool.lastUpdateTime = block.timestamp;
        globalPool.rewardRate = rewardRate;
        globalPool.weight = weight;
        emit RateUpdated(address(this), rewardRate, weight);
    }

    /// @notice Get current reserve amount of given pool
    /// @param poolId Pool Id, i.e., address of the Pair contract
    /// @return reserve Current reserve amount
    function getCurrentPoolReserve(address poolId) public view returns (uint reserve) {
        Pool storage pool = pools[poolId];
        reserve = (block.timestamp - pool.lastUpdateTime) * pool.rewardRate + pool.lastReserve;
    }

    /// @notice Get current reserve amount of gov token pool
    /// @return reserve Current reserve amount
    function getCurrentGlobalReserve() public view returns (uint reserve) {
        reserve = (block.timestamp - globalPool.lastUpdateTime) * globalPool.rewardRate + globalPool.lastReserve;
    }

    /// @dev Calculate reward amount with given amount, reserve amount and weight:
    /// reward = reserve * (1 - 2^(-amount/w))
    /// @param _reserve Reserve amount
    /// @param _amount LocalSP or GlobalSP amount
    /// @param _w Weight
    /// @return reward Reward amount in either globalSP or gov token
    function _calcRewardAmount(uint _reserve, uint _amount, uint _w) internal pure returns (uint reward) {
        int128 r = _amount.divu(_w);
        int128 e = (-r).exp_2();
        reward = (MAX_AP_RATIO - e).mulu(_reserve);
    }

    /// @notice Triggered by Pair contract to grant user SP upon user deposit
    /// If user also stake his sGov token, i.e., sDYSON token in the pool's Gauge contract, he will receive bouns localSP.
    /// @dev The pool's `lastReserve` and `lastUpdateTime` are updated each time `grantSP` is triggered 
    /// @param to User's address
    /// @param amount Amount of localSP
    function grantSP(address to, uint amount) external {
        if(agency.whois(to) == 0) return;
        Pool storage pool = pools[msg.sender];
        // check pool bonus
        uint bonus = IGauge(pool.gauge).bonus(to);
        if (bonus > 0) amount = amount * (bonus + BONUS_BASE_UNIT) / BONUS_BASE_UNIT;
        // swap localSP to globalSP
        uint reserve = getCurrentPoolReserve(msg.sender);
        uint SPAmount = _calcRewardAmount(reserve, amount, pool.weight);

        pool.lastReserve = reserve - SPAmount;
        pool.lastUpdateTime = block.timestamp;
        balanceOf[to] += SPAmount;
        emit GrantSP(to, msg.sender, amount, SPAmount);
    }

    /// @notice Swap given `user`'s SP to gov token.
    /// This can be done by a third party.
    /// User can only swap if his cooldown has ended. Cooldown time depends on user's generation in the referral system.
    /// User need to register in the referral system to be able to swap.
    /// User's referrer will receive 1/3 of user's SP upon swap.
    function swap(address user) external returns (uint amountOut) {
        require(block.timestamp > cooldown[user], "cd");
        if(agency.whois(user) == 0) return 0;
        (address ref, uint gen) = agency.userInfo(user);
        cooldown[user] = block.timestamp + (gen + 1) * CD;

        // swap sp to token
        uint reserve = getCurrentGlobalReserve();

        uint amountIn = balanceOf[user];
        balanceOf[user] = 0;
        require(amountIn > 0 ,"no sp");

        amountOut = _calcRewardAmount(reserve, amountIn, globalPool.weight);

        globalPool.lastReserve = reserve - amountOut;
        globalPool.lastUpdateTime = block.timestamp;
        // referral
        balanceOf[ref] += amountIn / 3;
        // mint token
        gov.mint(user, amountOut);
        emit Swap(user, ref, amountIn, amountOut);
    }

}
