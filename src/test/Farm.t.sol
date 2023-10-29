// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Farm.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";
import "../lib/SqrtMath.sol";
import "src/interface/IDYSON.sol";
import "./TestUtils.sol";

contract AgencyMock {
    mapping(address => uint) public whois;
    mapping(address => address) public ref;
    mapping(address => uint) public gen;

    function setWhois(address _agent, uint _id) external {
        whois[_agent] = _id;
    }

    function setUserInfo(address _agent, address _ref, uint _gen) external {
        ref[_agent] = _ref;
        gen[_agent] = _gen;
    }

    function userInfo(address _agent) external view returns (address _ref, uint _gen) {
        _ref = ref[_agent];
        _gen = gen[_agent];
    }
}

contract GaugeMock {
    uint private constant MAX_BONUS = 1.5e18;

    uint public weight;
    uint public nextRewardRate;
    mapping(address => uint) public bonus;

    function setBonus(address _to, uint _amount) external {
        if (_amount > MAX_BONUS) _amount = MAX_BONUS;
        bonus[_to] = _amount;
    }


    function setWeightAndNextRewardRate(uint _weight, uint _rewardRate) external {
        weight = _weight;
        nextRewardRate = _rewardRate;
    }
}

contract FarmTest is TestUtils {
    using ABDKMath64x64 for *;
    using SqrtMath for *;

    event GrantSP(address indexed user, address indexed poolId, uint amountIn, uint amountOut);
    event Swap(address indexed user, address indexed parent, uint amountIn, uint amountOut);

    address testOwner = address(this);
    DYSON gov = new DYSON(testOwner);
    AgencyMock agency = new AgencyMock();
    address pair = address(0x1000);
    address gauge = address(new GaugeMock());
    Farm farm = new Farm(testOwner, address(agency), address(gov));

    address alice = address(0x1001);

    uint constant CD = 6000;
    int128 constant MAX_AP_RATIO = 2**64;
    uint constant BONUS_BASE_UNIT = 1e18;

    uint constant DEFAULT_AGENT_ID = 5566;
    address constant DEFAULT_REFERRER = address(0x1234);
    uint constant DEFAULT_AGENT_GEN = 2;
    uint constant DEFAULT_POOL_WEIGHT = 123;
    uint constant DEFAULT_REWARD_RATE = 456;
    uint constant DEFAUL_BONUS = 1e18;

    function setUp() public {
        gov.addMinter(address(farm));
    }

    function testCannotTransferOnwnershipByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        farm.transferOwnership(alice);
    }

    function testTransferOnwnership() public {
        farm.transferOwnership(alice);
        assertEq(farm.owner(), alice);
    }

    function testCannotSetPoolByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        farm.setPool(pair, gauge);
    }

    function testSetPool() public {
        GaugeMock(gauge).setWeightAndNextRewardRate(DEFAULT_POOL_WEIGHT, DEFAULT_REWARD_RATE);

        farm.setPool(pair, gauge);
        (uint _weight, uint _rewardRate, uint _lastUpdateTime, uint _lastReserve, address _gauge) = farm.pools(pair);
        assertEq(_weight, DEFAULT_POOL_WEIGHT);
        assertEq(_rewardRate, DEFAULT_REWARD_RATE);
        assertEq(_lastUpdateTime, block.timestamp);
        assertEq(_lastReserve, 0);
        assertEq(_gauge, gauge);

        // Accrue reserve
        skip(1 weeks);
        uint reserve = farm.getCurrentPoolReserve(pair);
        assertEq(reserve, (1 weeks) * _rewardRate);
    }

    function testCannotSetPoolRewardRateByNonPoolGauge() public {
        farm.setPool(pair, gauge);

        vm.expectRevert("not gauge");
        farm.setPoolRewardRate(pair, DEFAULT_REWARD_RATE, DEFAULT_POOL_WEIGHT);
    }

    function testSetPoolRewardRate() public {
        farm.setPool(pair, gauge);

        vm.prank(gauge);
        farm.setPoolRewardRate(pair, DEFAULT_REWARD_RATE, DEFAULT_POOL_WEIGHT);
        (uint _weight, uint _rewardRate, , , ) = farm.pools(pair);
        assertEq(_weight, DEFAULT_POOL_WEIGHT);
        assertEq(_rewardRate, DEFAULT_REWARD_RATE);
    }

    function testCannotSetGlobalPoolRewardRateByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        farm.setGlobalRewardRate(DEFAULT_REWARD_RATE, DEFAULT_POOL_WEIGHT);
    }

    function testSetGlobalPoolRewardRate() public {
        farm.setGlobalRewardRate(DEFAULT_REWARD_RATE, DEFAULT_POOL_WEIGHT);
        (uint _weight, uint _rewardRate, uint _lastUpdateTime, uint _lastReserve, address _gauge) = farm.globalPool();
        assertEq(_weight, DEFAULT_POOL_WEIGHT);
        assertEq(_rewardRate, DEFAULT_REWARD_RATE);
        assertEq(_lastUpdateTime, block.timestamp);
        assertEq(_lastReserve, 0);
        assertEq(_gauge, address(0));

        // Accrue reserve
        skip(1 weeks);
        uint reserve = farm.getCurrentGlobalReserve();
        assertEq(reserve, (1 weeks) * _rewardRate);
    }

    function testGrantSPWithNoBonus() public {
        _setupPool();
        agency.setWhois(alice, DEFAULT_AGENT_ID);

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        uint reserveBefore = farm.getCurrentPoolReserve(pair);
        uint aliceBalanceBefore = farm.balanceOf(alice);
        uint expectedAPAmount = _calcRewardAmount(reserveBefore, amount, DEFAULT_POOL_WEIGHT);

        vm.expectEmit(true, true, false, true);
        emit GrantSP(alice, pair, amount, expectedAPAmount);

        _grantSP(alice, amount);

        uint reserveAfter = farm.getCurrentPoolReserve(pair);
        uint aliceBalanceAfter = farm.balanceOf(alice);
        (, , uint _lastUpdateTime, ,) = farm.pools(pair);

        assertEq(_lastUpdateTime, block.timestamp);
        assertEq(reserveAfter, reserveBefore - expectedAPAmount);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + expectedAPAmount);
    }

    function testGrantSPWithBonus() public {
        _setupPool();
        agency.setWhois(alice, DEFAULT_AGENT_ID);
        GaugeMock(gauge).setBonus(alice, DEFAUL_BONUS);

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        uint reserveBefore = farm.getCurrentPoolReserve(pair);
        uint aliceBalanceBefore = farm.balanceOf(alice);
        uint expectedAPAmount = _calcRewardAmount(reserveBefore, _caluAmountWithBonus(amount, DEFAUL_BONUS), DEFAULT_POOL_WEIGHT);

        vm.expectEmit(true, true, false, true);
        emit GrantSP(alice, pair, _caluAmountWithBonus(amount, DEFAUL_BONUS), expectedAPAmount);

        _grantSP(alice, amount);
        uint reserveAfter = farm.getCurrentPoolReserve(pair);

        uint aliceBalanceAfter = farm.balanceOf(alice);
        (, , uint _lastUpdateTime, ,) = farm.pools(pair);

        assertEq(_lastUpdateTime, block.timestamp);
        assertEq(reserveAfter, reserveBefore - expectedAPAmount);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + expectedAPAmount);
    }

    function testGrantSPByNonPool() public {
        _setupPool();
        _setupUserAgent(alice);

        // Accrue reserve
        skip(1 weeks);

        vm.expectRevert();
        uint amount = 100 * 1e18;
        farm.grantSP(alice, amount);
    }

    function testGrantSPNoopIfUserNotAgent() public {
        _setupPool();

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        uint reserveBefore = farm.getCurrentPoolReserve(pair);
        uint aliceBalanceBefore = farm.balanceOf(alice);

        _grantSP(alice, amount);

        uint reserveAfter = farm.getCurrentPoolReserve(pair);
        uint aliceBalanceAfter = farm.balanceOf(alice);

        assertEq(reserveAfter, reserveBefore);
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
    }

    function testCannotSwapGloablAPIfNoBalance() public {
        _setupGlobalPool();
        _setupPool();
        _setupUserAgent(alice);

        // Accrue reserve
        skip(1 weeks);

        vm.expectRevert("no sp");
        farm.swap(alice);
    }

    function testSwapGlobalAP() public {
        _setupGlobalPool();
        _setupPool();
        _setupUserAgent(alice);

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        _grantSP(alice, amount);

        uint globalReserveBefore = farm.getCurrentGlobalReserve();
        uint aliceBalanceBefore = farm.balanceOf(alice);
        uint aliceGovBalanceBefore = gov.balanceOf(alice);
        uint referrerBalanceBefore = farm.balanceOf(DEFAULT_REFERRER);
        uint expectedRewardAmount = _calcRewardAmount(globalReserveBefore, amount, DEFAULT_POOL_WEIGHT);

        vm.expectEmit(true, true, false, true);
        emit Swap(alice, DEFAULT_REFERRER, aliceBalanceBefore, expectedRewardAmount);

        farm.swap(alice);

        uint globalReserveAfter = farm.getCurrentGlobalReserve();
        uint aliceBalanceAfter = farm.balanceOf(alice);
        uint referrerBalanceAfter = farm.balanceOf(DEFAULT_REFERRER);
        uint aliceGovBalanceAfter = gov.balanceOf(alice);
        (, , uint _lastUpdateTime, ,) = farm.pools(pair);
        uint aliceCooldownAfter = farm.cooldown(alice);

        assertEq(_lastUpdateTime, block.timestamp);
        assertEq(globalReserveAfter, globalReserveBefore - expectedRewardAmount);
        assertEq(aliceBalanceAfter, 0);
        assertEq(aliceGovBalanceAfter, aliceGovBalanceBefore + expectedRewardAmount);
        assertEq(referrerBalanceAfter, referrerBalanceBefore + expectedRewardAmount / 3);
        assertEq(aliceCooldownAfter, block.timestamp + (DEFAULT_AGENT_GEN + 1) * CD);
    }

    function testSwapGloablAPNoopIfUserNotAgent() public {
        _setupGlobalPool();
        _setupPool();
        _setupUserAgent(alice);

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        _grantSP(alice, amount);

        // User transfer away his agent
        agency.setWhois(alice, 0);
        agency.setUserInfo(alice, address(0), 0);

        uint globalReserveBefore = farm.getCurrentGlobalReserve();
        uint aliceBalanceBefore = farm.balanceOf(alice);
        uint aliceGovBalanceBefore = gov.balanceOf(alice);

        farm.swap(alice);

        uint globalReserveAfter = farm.getCurrentGlobalReserve();
        uint aliceBalanceAfter = farm.balanceOf(alice);
        uint aliceGovBalanceAfter = gov.balanceOf(alice);
        uint aliceCooldownAfter = farm.cooldown(alice);

        assertEq(globalReserveAfter, globalReserveBefore);
        assertEq(aliceBalanceAfter, aliceBalanceBefore);
        assertEq(aliceGovBalanceAfter, aliceGovBalanceBefore);
        assertEq(aliceCooldownAfter, 0);
    }

    function testFailCannotSwapGloablAPBeforeCooldownEnds() public {
        _setupGlobalPool();
        _setupPool();
        _setupUserAgent(alice);

        // Accrue reserve
        skip(1 weeks);

        uint amount = 100 * 1e18;
        _grantSP(alice, amount);

        // First swap will succeed
        farm.swap(alice);

        // Second swap will fail because user's cooldown hasn't end
        // Can not use `expectRevert`, strange error thrown: Member "expectRevert" not unique after argument-dependent lookup in contract Vm.
        // Replace `expectRevert` with Prefixing test name with `Fail`
        // vm.expectRevert("CD");
        farm.swap(alice);
    }

    function _setupUserAgent(address _user) internal {
        agency.setWhois(_user, DEFAULT_AGENT_ID);
        agency.setUserInfo(_user, DEFAULT_REFERRER, DEFAULT_AGENT_GEN);
    }

    function _setupPool() internal {
        GaugeMock(gauge).setWeightAndNextRewardRate(DEFAULT_POOL_WEIGHT, DEFAULT_REWARD_RATE);
        farm.setPool(pair, gauge);
    }

    function _setupGlobalPool() internal {
        farm.setGlobalRewardRate(DEFAULT_REWARD_RATE, DEFAULT_POOL_WEIGHT);
    }

    function _calcRewardAmount(uint _reserve, uint _amount, uint _w) internal returns (uint reward) {
        int128 r = _amount.divu(_w);
        int128 e = (-r).exp_2();
        reward = (MAX_AP_RATIO - e).mulu(_reserve);
        assertGt(reward, 0);
    }

    function _caluAmountWithBonus(uint _amount, uint _bonus) internal pure returns (uint) {
        if (_bonus > 0) _amount = _amount * (_bonus + BONUS_BASE_UNIT) / BONUS_BASE_UNIT;
        return _amount;
    }

    function _grantSP(address _user, uint _amount) internal {
        vm.prank(pair);
        farm.grantSP(_user, _amount);
    }
}