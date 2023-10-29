// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Gauge.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";
import "src/GaugeFactory.sol";
import "src/lib/SqrtMath.sol";
import "src/interface/IERC20.sol";
import "./TestUtils.sol";

contract FarmMock {
    function setPoolRewardRate(address, uint, uint) pure external {}
}

contract GaugeTest is TestUtils {
    using SqrtMath for *;

    address testOwner = address(this);
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address farm = address(new FarmMock());
    uint constant INITIAL_WEIGHT = 10**24;
    uint constant INITIAL_BASE = 10**24;
    uint constant INITIAL_SLOPE = 10**24;
    GaugeFactory factory = new GaugeFactory(testOwner);
    Gauge gauge = Gauge(factory.createGauge(farm, sGov, address(0), INITIAL_WEIGHT, INITIAL_BASE, INITIAL_SLOPE));

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");

    uint immutable INITIAL_WEALTH = 10**30;

    uint constant REWARD_RATE_BASE_UNIT = 1e18;
    uint constant BONUS_MULTIPLIER = 22.5e36;
    uint constant MAX_BONUS = 1.5e18;
    uint genesis;

    function setUp() public {
        deal(sGov, alice, INITIAL_WEALTH);
        deal(sGov, bob, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(sGov).approve(address(gauge), INITIAL_WEALTH);
        changePrank(bob);
        IERC20(sGov).approve(address(gauge), INITIAL_WEALTH);
        vm.stopPrank();
        genesis = gauge.genesis();
    }

    function testCreateGauge() public {
        address _gauge = factory.createGauge(farm, sGov, address(0), 0, 0, 0);
        assertEq(Gauge(_gauge).owner(), factory.controller());
    }

    function testCannotCreateGaugeByNonController() public {
        vm.startPrank(alice);
        vm.expectRevert("forbidden");
        factory.createGauge(farm, sGov, address(0), 0, 0, 0);
    }

    function testSetFactoryController() public {
        factory.setController(alice);
        vm.prank(alice);
        factory.becomeController();
        assertEq(factory.controller(), alice);
    }

    function testCannotTransferOnwnershipByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        gauge.transferOwnership(alice);
    }

    function testTransferOnwnership() public {
        gauge.transferOwnership(alice);
        assertEq(gauge.owner(), alice);
    }

    function testCannotSetParamsByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        gauge.setParams(0, 0, 0);
    }

    function testSetParams() public {
        gauge.setParams(1, 2, 3);
        assertEq(gauge.weight(), 1);
        assertEq(gauge.base(), 2);
        assertEq(gauge.slope(), 3);
    }

    function testBalanceOfZero() public {
        assertEq(gauge.balanceOf(alice), 0);
    }

    function testCannotBalanceOfAtBeforeRealWeek() public {
        skip(2 weeks);
        // Since no tick(), thisWeek = 0, realWeek = 2
        vm.expectRevert("not yet");
        gauge.balanceOfAt(alice, 2 + genesis);
    }

    function testCannotBalanceOfAtBeforeThisWeek() public {
        skip(2 weeks);
        // Since no tick(), thisWeek = 0, realWeek = 2
        vm.expectRevert("not yet");
        gauge.balanceOfAt(alice, 1 + genesis);
    }

    function testNextRewardRate() public {
        assertEq(gauge.nextRewardRate(), INITIAL_BASE);

        vm.prank(alice);
        gauge.deposit(1, alice);
        vm.prank(bob);
        gauge.deposit(2, bob);
        skip(1 weeks);

        // rewardRate = totalSupply * slope + base
        assertEq(gauge.nextRewardRate(), 3 * INITIAL_SLOPE / REWARD_RATE_BASE_UNIT + INITIAL_BASE);
    }

    function testCannotDepositZero() public {
        vm.prank(alice);
        vm.expectRevert("cannot deposit 0");
        gauge.deposit(0, alice);
    }

    function testDeposit() public {
        // Week Balance
        //  0      1
        //  1      4
        //  3      9
        vm.startPrank(alice);
        gauge.deposit(1, alice);
        skip(1 weeks);
        gauge.deposit(3, alice);
        skip(2 weeks);
        gauge.deposit(5, alice);
        skip(1 weeks);
        gauge.tick();
        vm.stopPrank();

        assertEq(gauge.balanceOfAt(alice, genesis), 1);
        assertEq(gauge.balanceOfAt(alice, 1 + genesis), 4);
        assertEq(gauge.balanceOfAt(alice, 2 + genesis), 4);
        assertEq(gauge.balanceOfAt(alice, 3 + genesis), 9);
        assertEq(gauge.balanceOf(alice), 9);

        assertEq(gauge.totalSupplyAt(genesis), 1);
        assertEq(gauge.totalSupplyAt(1 + genesis), 4);
        assertEq(gauge.totalSupplyAt(2 + genesis), 4);
        assertEq(gauge.totalSupplyAt(3 + genesis), 9);
        assertEq(gauge.totalSupply(), 9);
    }

    function testCannotApplyWithdrawZero() public{
        vm.startPrank(alice);
        gauge.deposit(1, alice);
        vm.expectRevert("cannot withdraw 0");
        gauge.applyWithdrawal(0);
    }

    function testCannotApplyWithdrawWithoutAnyDeposit() public {
        vm.prank(alice);
        vm.expectRevert("cannot withdraw more than balance");
        gauge.applyWithdrawal(1);        
    }

    function testCannotApplyWithdrawLargerThanBalance() public {
        vm.startPrank(alice);
        gauge.deposit(1, alice);
        vm.expectRevert("cannot withdraw more than balance");
        gauge.applyWithdrawal(2);        
    }

    function testCannotWithdrawZero() public {
        vm.startPrank(alice);
        gauge.deposit(1, alice);
        vm.expectRevert("cannot withdraw 0");
        gauge.withdraw();
    }

    function testCannotWithdrawBeforeNextWeek() public {
        vm.startPrank(alice);
        gauge.deposit(1, alice);
        skip(1 days);

        gauge.applyWithdrawal(1);
        vm.expectRevert("not yet");
        gauge.withdraw();
    }

    function testWithdraw() public {
        uint DEPOSIT_VALUE = 10;
        uint WITHDRAW_VALUE = 6;
        vm.startPrank(alice);
        gauge.deposit(DEPOSIT_VALUE, alice);

        uint sGovBalanceBefore = IERC20(sGov).balanceOf(alice);
        gauge.applyWithdrawal(WITHDRAW_VALUE);
        assertEq(gauge.balanceOf(alice), DEPOSIT_VALUE - WITHDRAW_VALUE);
        assertEq(gauge.totalSupply(), DEPOSIT_VALUE - WITHDRAW_VALUE);
        assertEq(IERC20(sGov).balanceOf(alice), sGovBalanceBefore);

        skip(1 weeks);
        gauge.withdraw();
        uint sGovBalanceAfter = IERC20(sGov).balanceOf(alice);
        assertEq(sGovBalanceAfter - sGovBalanceBefore, WITHDRAW_VALUE);
    }

    function testBonusFuzzing(uint balance) public {
        // Alice deposits 1000.
        // Bob deposits balance(fuzzing).
        vm.assume(balance < INITIAL_WEALTH);
        vm.assume(balance > 0);

        vm.prank(alice);
        gauge.deposit(1000, alice);
        vm.prank(bob);
        gauge.deposit(balance, bob);

        uint totalSupply = 1000 + balance;
        uint bonus = (1000 * BONUS_MULTIPLIER / totalSupply).sqrt();
        bonus = bonus > MAX_BONUS ? MAX_BONUS : bonus;
        assertEq(gauge.bonus(alice), bonus);
    }
}