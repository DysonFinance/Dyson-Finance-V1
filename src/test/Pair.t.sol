// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Pair.sol";
import "src/Factory.sol";
import "src/DYSON.sol";
import "./TestUtils.sol";

contract PairTest is TestUtils {
    address testOwner = address(this);
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    Factory factory = new Factory(testOwner);
    Pair pair = Pair(factory.createPair(token0, token1));

    uint immutable INITIAL_LIQUIDITY_TOKEN0 = 10**24;
    uint immutable INITIAL_LIQUIDITY_TOKEN1 = 10**24;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");

    uint immutable INITIAL_WEALTH = 10**30;

    function setUp() public {
        // Initialize liquidity of Pair.
        deal(token0, address(pair), INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, address(pair), INITIAL_LIQUIDITY_TOKEN1);

        // Initialize handy accounts for testing.
        deal(token0, alice, INITIAL_WEALTH);
        deal(token1, alice, INITIAL_WEALTH);
        deal(token0, bob, INITIAL_WEALTH);
        deal(token1, bob, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(token0).approve(address(pair), INITIAL_WEALTH);
        IERC20(token1).approve(address(pair), INITIAL_WEALTH);
        changePrank(bob);
        IERC20(token0).approve(address(pair), INITIAL_WEALTH);
        IERC20(token1).approve(address(pair), INITIAL_WEALTH);
        vm.stopPrank();
    }

    function testCannotDepositIfSlippageTooHigh() public {
        uint depositAmount = 10 * 10**18;
        vm.prank(bob);
        vm.expectRevert("slippage");
        pair.deposit0(bob, depositAmount, depositAmount, 1 days);
        vm.expectRevert("slippage");
        pair.deposit1(bob, depositAmount, depositAmount, 1 days);
    }

    function testCannotDepositWithInvalidPeriod() public {
        uint depositAmount = 10 * 10**18;
        vm.prank(bob);
        vm.expectRevert("invalid time");
        pair.deposit0(bob, depositAmount, 0, 2 days);
        vm.expectRevert("invalid time");
        pair.deposit1(bob, depositAmount, 0, 2 days);
    }

    function testDeposit0() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days);
        pair.deposit0(bob, depositAmount, 0, 3 days);
        pair.deposit0(bob, depositAmount, 0, 7 days);
        pair.deposit0(bob, depositAmount, 0, 30 days);
    }

    function testDeposit1() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit1(bob, depositAmount, 0, 1 days);
        pair.deposit1(bob, depositAmount, 0, 3 days);
        pair.deposit1(bob, depositAmount, 0, 7 days);
        pair.deposit1(bob, depositAmount, 0, 30 days);
    }

    function testCannotWithdrawNonExistNote() public {
        vm.startPrank(bob);
        vm.expectRevert("invalid note");
        pair.withdraw(0, testOwner);
        vm.expectRevert("invalid note");
        pair.withdraw(1, testOwner);
    }

    function testCannotEarlyWithdraw() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days); // Note 0
        pair.deposit1(bob, depositAmount, 0, 1 days); // Note 1

        vm.expectRevert("early withdrawal");
        pair.withdraw(0, testOwner);
        vm.expectRevert("early withdrawal");
        pair.withdraw(1, testOwner);
    }

    function testWithdraw0() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days);

        skip(1 days);
        pair.withdraw(0, testOwner);
    }

    function testWithdraw1() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit1(bob, depositAmount, 0, 1 days);

        skip(1 days);
        pair.withdraw(0, testOwner);
    }

    function testCannotWithdrawSameNote() public {
        uint depositAmount = 10 * 10**18;
        vm.startPrank(bob);
        pair.deposit0(bob, depositAmount, 0, 1 days); // Note 0
        pair.deposit1(bob, depositAmount, 0, 1 days); // Note 1

        skip(1 days);
        pair.withdraw(0, testOwner);
        pair.withdraw(1, testOwner);
        vm.expectRevert("invalid note");
        pair.withdraw(0, testOwner);
        vm.expectRevert("invalid note");
        pair.withdraw(1, testOwner);
    }

    function testCannotSetBasisByUser() public {
        vm.prank(bob);
        vm.expectRevert("forbidden");
        pair.setBasis(0);
    }

    function testCannotSetHalfLifeByUser() public {
        vm.prank(bob);
        vm.expectRevert("forbidden");
        pair.setHalfLife(0);
    }

    function testCannotSetFarmByUser() public {
        vm.prank(bob);
        vm.expectRevert("forbidden");
        pair.setFarm(address(0));
    }

    function testCannotSetFeeToByUser() public {
        vm.prank(bob);
        vm.expectRevert("forbidden");
        pair.setFeeTo(address(0));
    }

    function testRescueERC20() public {
        address token2 = address(new DYSON(testOwner));
        deal(token2, address(pair), INITIAL_WEALTH);
        pair.rescueERC20(token2, bob, INITIAL_WEALTH);
        assertEq(IERC20(token2).balanceOf(bob), INITIAL_WEALTH);
    }

    function testCannotSwapIfSlippageTooHigh() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        vm.expectRevert("slippage");
        output1 = pair.swap0in(bob, swapAmount, swapAmount);
        vm.expectRevert("slippage");
        output0 = pair.swap1in(bob, swapAmount, swapAmount);
    }

    function testSwap01() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        output1 = pair.swap0in(bob, swapAmount, 0);
        output0 = pair.swap1in(bob, output1, 0);
        assertTrue(output0 <= swapAmount);

        changePrank(alice);
        output1 = pair.swap0in(alice, swapAmount, 0);
        skip(1 hours);
        output0 = pair.swap1in(alice, output1, 0);
        assertTrue(output0 <= swapAmount);
    }

    function testSwap10() public {
        uint swapAmount = 10 * 10**18;
        uint output0; 
        uint output1;
        vm.startPrank(bob);
        vm.expectRevert("slippage");
        output0 = pair.swap1in(bob, swapAmount, swapAmount);
        output0 = pair.swap1in(bob, swapAmount, 0);
        output1 = pair.swap0in(bob, output0, 0);
        assertTrue(output1 <= swapAmount);

        changePrank(alice);
        output0 = pair.swap1in(alice, swapAmount, 0);
        skip(1 hours);
        output1 = pair.swap0in(alice, output0, 0);
        assertTrue(output1 <= swapAmount);
    }
}