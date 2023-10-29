// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "util/ICO.sol";
import "src/lib/SqrtMath.sol";
import "src/DYSON.sol";

contract ICOTest is Test {
    using SqrtMath for *;
    ICO ico;
    DYSON token0;
    DYSON token1;
    DYSON dysn;
    uint dysnTotalSupply = 10000e18;
    uint startTime;
    uint duration = 7 days;
    // sqrt(k), k = xy = xy * 1e18 * 1e18 , so the unit is sqrt(1e36) = 1e18
    uint startingMaxUnits = 10000e18; 
    uint endingMaxUnits = 100e18;

    address owner = address(this);
    address alice;
    address bob;
    uint fundToken1 = 10000000e18;
    uint fundToken0 = 100e18;
    
    function setUp() public {
        // assume dyson is the token to ICO
        address testOwner = address(this);
        startTime = block.timestamp + 1 days;
        token0 = new DYSON(testOwner);
        token1 = new DYSON(testOwner);
        dysn = new DYSON(testOwner);
        ico = new ICOStrategy(owner, address(token1), address(token0), dysnTotalSupply, startTime, duration, address(dysn), startingMaxUnits, endingMaxUnits);
        alice = vm.addr(1);
        bob = vm.addr(2);

        vm.startPrank(alice);
        token0.approve(address(ico), fundToken0);
        token1.approve(address(ico), fundToken1);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(ico), fundToken0);
        token1.approve(address(ico), fundToken1);
        vm.stopPrank();

        deal(address(token0), alice, fundToken0);
        deal(address(token1), alice, fundToken1);
        deal(address(token0), bob, fundToken0);
        deal(address(token1), bob, fundToken1);
        deal(address(dysn), address(ico), dysnTotalSupply);

        assertEq(token0.balanceOf(address(alice)), fundToken0);
        assertEq(token1.balanceOf(address(alice)), fundToken1);
        assertEq(token0.balanceOf(address(bob)), fundToken0);
        assertEq(token1.balanceOf(address(bob)), fundToken1);
        assertEq(dysn.balanceOf(address(ico)), dysnTotalSupply);
    }

    function testDeposit() public {
        uint deposit0 = 10000e18;
        uint deposit1 = 100e18;
        uint share = (deposit0 * deposit1).sqrt();
        vm.warp(startTime);

        vm.prank(alice);
        ico.deposit(deposit0, deposit1, 0);
        assertEq(ico.reserve0(), deposit0);
        assertEq(ico.reserve1(), deposit1);
        assertEq(ico.getCurrentUnits(deposit0, deposit1), share);
        assertEq(ico.getCurrentMaxUnits(), startingMaxUnits);
        assertEq(ico.shareOf(alice), share);
    }

    function testDepositRevertWhenNotStarted() public {
        uint deposit0 = 10000e18;
        uint deposit1 = 100e18;
        vm.warp(startTime - 1);
        vm.expectRevert("ICO: NOT_STARTED_YET");
        ico.deposit(deposit0, deposit1, 0);
    }

    function testDepositRevertWhenEnded() public {
        uint deposit0 = 10000e18;
        uint deposit1 = 100e18;
        vm.warp(startTime + duration + 1);
        vm.expectRevert("ICO: ALREADY_ENDED");
        ico.deposit(deposit0, deposit1, 0);
    }

    function testDepositRevertWhenTokenAmtIsZero() public {
        vm.warp(startTime);
        vm.expectRevert("ICO: AMOUNTS_OF_BOTH_TOKENS_ARE_ZERO");
        ico.deposit(0, 0, 0);
    }

    function testDepositRevertWhenShareUnitsLessThanMinUnits() public {
        uint deposit0 = 0;
        uint deposit1 = 50e18;
        // fund the liquidity first
        vm.warp(startTime);
        vm.prank(alice);
        ico.deposit(10000e18, 10e18, 0);

        uint reserve0 = ico.reserve0();
        uint reserve1 = ico.reserve1();
        uint share = ico.calculateNewShare(reserve0, reserve1, deposit0, deposit1);
        uint minShare = share * 9 / 10; // set the slippage to 10%
        
        vm.prank(bob);
        ico.deposit(0, 100e18, 0);

        vm.expectRevert("ICO: SHARE_LESS_THAN_MINUNITS");
        vm.prank(alice);
        ico.deposit(deposit0, deposit1, minShare);
    }

    function testDepositRevertWhenExceedMaxUnits() public {
        uint deposit0 = 100000e18;
        uint deposit1 = 100e18;
        vm.warp(startTime + 4 days); // max units = 43428571429

        vm.prank(alice);
        ico.deposit(deposit0, deposit1, 0); // current units = 31622776601

        vm.prank(bob);
        vm.expectRevert("ICO: TOTAL_UNITS_EXCEED_MAXUNITS");
        ico.deposit(deposit0, deposit1, 0); // current units = 63245553202 > max units
    }

    function testDepositRevertWhenInsufficientLiquidity() public {
        uint deposit0 = 0;
        uint deposit1 = 100e18;
        vm.warp(startTime);
        vm.prank(alice);
        vm.expectRevert("ICO: INSUFFICIENT_LIQUIDITY");
        ico.deposit(deposit0, deposit1, 0);
    }

    function testClaim() public {
        uint aliceDeposit0 = 10000e18;
        uint aliceDeposit1 = 100e18;
        uint bobDeposit0 = 5000e18;
        uint bobDeposit1 = 50e18;
        vm.warp(startTime);

        vm.prank(alice);
        ico.deposit(aliceDeposit0, aliceDeposit1, 0);
        vm.prank(bob);
        ico.deposit(bobDeposit0, bobDeposit1, 0);

        vm.warp(startTime + duration + 1);
        vm.prank(alice);
        ico.claim();
        vm.prank(bob);
        ico.claim();

        uint aliceUnits = (aliceDeposit0 * aliceDeposit1).sqrt();
        uint bobUnits = (bobDeposit0 * bobDeposit1).sqrt();
        uint totalUnits = aliceUnits + bobUnits;

        uint aliceDysnShare = dysnTotalSupply * aliceUnits / totalUnits;
        uint bobDysnShare = dysnTotalSupply * bobUnits / totalUnits;
        assertEq(dysn.balanceOf(address(alice)), aliceDysnShare);
        assertEq(dysn.balanceOf(address(bob)), bobDysnShare);
    }

    function testClaimRevertWhenNotEnded() public {
        uint deposit0 = 10000e18;
        uint deposit1 = 100e18;
        vm.warp(startTime);
        vm.prank(alice);
        ico.deposit(deposit0, deposit1, 0);
        vm.expectRevert("ICO: NOT_ENDED_YET");
        ico.claim();
    }

    function testClaimRevertWhenNoShare() public {
        vm.warp(startTime + duration + 1);
        vm.expectRevert("ICO: NO_SHARE");
        ico.claim();
    }

    function testOwnerClaim() public {
        uint aliceDeposit0 = 10000e18;
        uint aliceDeposit1 = 100e18;
        uint bobDeposit0 = 5000e18;
        uint bobDeposit1 = 50e18;
        vm.warp(startTime);
        vm.prank(alice);
        ico.deposit(aliceDeposit0, aliceDeposit1, 0);
        vm.prank(bob);
        ico.deposit(bobDeposit0, bobDeposit1, 0);

        vm.warp(startTime + duration + 1);
        ico.ownerClaim(owner);
        assertEq(token0.balanceOf(owner), 150e18); // aliceDeposit1 + bobDeposit1
        assertEq(token1.balanceOf(owner), 15000e18); // aliceDeposit0 + bobDeposit0
    }

    function testMaxUnitsDeclineWithLinearInterpolation() public {
        vm.warp(startTime);
        assertEq(ico.getCurrentMaxUnits(), startingMaxUnits);

        vm.warp(startTime + duration / 2);
        assertEq(ico.getCurrentMaxUnits(), (startingMaxUnits + endingMaxUnits) / 2);

        vm.warp(startTime + duration);
        assertEq(ico.getCurrentMaxUnits(), endingMaxUnits);
    }


}