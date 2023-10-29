// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Bribe.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";
import "src/Gauge.sol";
import "src/BribeFactory.sol";
import "src/GaugeFactory.sol";
import "./TestUtils.sol";

contract FarmMock {
    function setPoolRewardRate(address, uint, uint) pure external {}
}

contract BribeTest is TestUtils {
    address testOwner = address(this);
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address farm = address(new FarmMock());
    uint constant INITIAL_WEIGHT = 10**24;
    uint constant INITIAL_BASE = 10**24;
    uint constant INITIAL_SLOPE = 10**24;
    BribeFactory bribeFactory = new BribeFactory(testOwner);
    GaugeFactory gaugeFactory = new GaugeFactory(testOwner);
    address gauge = gaugeFactory.createGauge(farm, sGov, address(0), INITIAL_WEIGHT, INITIAL_BASE, INITIAL_SLOPE);
    address bribe = bribeFactory.createBribe(gauge);
    address bribeToken = address(new DYSON(testOwner));

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address briber = _nameToAddr("briber");
    uint constant INITIAL_WEALTH = 10**30;
    uint genesis;

    function setUp() public {
        deal(sGov, alice, INITIAL_WEALTH);
        deal(sGov, bob, INITIAL_WEALTH);
        vm.prank(alice);
        sDYSON(sGov).approve(gauge, INITIAL_WEALTH);
        vm.prank(bob);
        sDYSON(sGov).approve(gauge, INITIAL_WEALTH);

        deal(bribeToken, briber, INITIAL_WEALTH);
        vm.prank(briber);
        DYSON(bribeToken).approve(bribe, INITIAL_WEALTH);
        genesis = Gauge(gauge).genesis();
    }

    function testCreateBribe() public {
        address _gauge = gaugeFactory.createGauge(farm, sGov, address(0), 0, 0, 0);
        address _bribe = bribeFactory.createBribe(_gauge);
        assertEq(address(Bribe(_bribe).gauge()), _gauge);
    }

    function testCannotCreateBribeByNonController() public {
        vm.startPrank(alice);
        vm.expectRevert("forbidden");
        bribeFactory.createBribe(address(0));
    }

    function testSetController() public {
        bribeFactory.setController(alice);
        vm.prank(alice);
        bribeFactory.becomeController();
        assertEq(bribeFactory.controller(), alice);
    }

    function testCannotAddRewardForPreviousWeeks() public {
        skip(2 weeks);
        uint bribeWeek = 1 + genesis;
        uint bribeAmount = 100;
        vm.prank(briber);
        vm.expectRevert("cannot add for previous weeks");
        Bribe(bribe).addReward(bribeToken, bribeWeek, bribeAmount);
    }

    function testAddReward() public {
        uint bribeWeek = 1 + genesis;
        uint bribeAmount = 100;
        vm.prank(briber);
        Bribe(bribe).addReward(bribeToken, bribeWeek, bribeAmount);
        assertEq(Bribe(bribe).tokenRewardOfWeek(bribeToken, bribeWeek), bribeAmount);
    }

    function testCannotClaimBeforeWeekEnds() public {
        // thisWeek = 0
        uint thisWeek = genesis;
        uint weekNotEnded = 1 + genesis;
        vm.prank(alice);
        vm.expectRevert("not yet");
        Bribe(bribe).claimReward(bribeToken, thisWeek);
        vm.expectRevert("not yet");
        Bribe(bribe).claimReward(bribeToken, weekNotEnded);
    }

    function testCannotClaimTwice() public {
        vm.startPrank(alice);
        Gauge(gauge).deposit(1, alice); // Avoid division by zero.
        skip(1 weeks);
        Bribe(bribe).claimReward(bribeToken, genesis);
        vm.expectRevert("claimed");
        Bribe(bribe).claimReward(bribeToken, genesis);
    }

    function testClaimReward() public {
        uint bribeAmount = 100;
        uint bribeWeek = genesis;
        vm.startPrank(briber);
        Bribe(bribe).addReward(bribeToken, bribeWeek, bribeAmount);
        Bribe(bribe).addReward(bribeToken, bribeWeek + 1, bribeAmount);
        Bribe(bribe).addReward(bribeToken, bribeWeek + 2, bribeAmount);

        // Week  Alice  Bob  TotalSupply  Bribe
        //  0      1     0         1       100
        //  1      1     3         4       100
        //  2      3     7        10       100
        //  thisWeek = 3
        changePrank(alice);
        Gauge(gauge).deposit(1, alice);
        skip(1 weeks);
        changePrank(bob);
        Gauge(gauge).deposit(3, bob);
        skip(1 weeks);
        changePrank(alice);
        Gauge(gauge).deposit(2, alice);
        changePrank(bob);
        Gauge(gauge).deposit(4, bob);
        skip(1 weeks);
        Gauge(gauge).tick();

        changePrank(alice);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek), bribeAmount);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek + 1), bribeAmount / 4);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount + bribeAmount / 4);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek + 2), bribeAmount * 3 / 10);
        assertEq(DYSON(bribeToken).balanceOf(alice), bribeAmount + bribeAmount / 4 + bribeAmount * 3 / 10);

        changePrank(bob);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek), 0);
        assertEq(DYSON(bribeToken).balanceOf(bob), 0);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek + 1), bribeAmount * 3/ 4);
        assertEq(DYSON(bribeToken).balanceOf(bob), bribeAmount * 3 / 4);
        assertEq(Bribe(bribe).claimReward(bribeToken, bribeWeek + 2), bribeAmount * 7 / 10);
        assertEq(DYSON(bribeToken).balanceOf(bob), bribeAmount * 3 / 4 + bribeAmount * 7 / 10);
    }
}