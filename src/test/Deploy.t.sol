// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "interface/IERC20.sol";
import "interface/IWETH.sol";
import "../Deploy.sol";
import "../Gauge.sol";
import "../Bribe.sol";
import "./TestUtils.sol";

contract WETHMock is DYSON {
    constructor(address owner) DYSON(owner) {}
    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint amount) public {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
}

contract DeployTest is TestUtils {
    address testOwner = address(this);
    address WETH = address(new WETHMock(testOwner));
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    address weth = address(new WETHMock(testOwner));
    Deploy deploy;

    uint constant WEIGHT = 3450e18;
    uint constant BASE = 5e18;
    uint constant SLOPE = 0.0000009e18;
    uint constant GLOBALRATE = 0.951e18;
    uint constant GLOBALWEIGHT = 821917e18;
    uint constant INITIAL_LIQUIDITY_TOKEN0 = 10**24;
    uint constant INITIAL_LIQUIDITY_TOKEN1 = 10**27;
    // assume token0 : token1 = 1 : 1000

    Agency agency;
    Factory factory;
    DYSON dyson;
    sDYSON sdyson;
    Router router;
    Farm farm;

    address pair;
    address gauge;
    address bribe;

    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");

    function setUp() public {
        deploy = new Deploy(testOwner, testOwner, WETH);

        agency = deploy.agency();
        factory = deploy.factory();
        dyson = deploy.dyson();
        sdyson = deploy.sdyson();
        router = deploy.router();
        farm = deploy.farm();

        if(token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        pair = factory.createPair(token0, token1);
        Pair(pair).setFarm(address(farm));
        gauge = address(new Gauge(address(farm), address(sdyson), pair, WEIGHT, BASE, SLOPE));
        bribe = address(new Bribe(gauge));
        farm.setPool(pair, gauge);
        farm.setGlobalRewardRate(GLOBALRATE, GLOBALWEIGHT);
        dyson.addMinter(address(farm));

        agency.adminAdd(alice);

        skip(1 days);

        deal(token0, pair, INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, pair, INITIAL_LIQUIDITY_TOKEN1);
        deal(token0, alice, INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, alice, INITIAL_LIQUIDITY_TOKEN1);
        deal(address(dyson), alice, INITIAL_LIQUIDITY_TOKEN0);
        deal(token0, bob, INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, bob, INITIAL_LIQUIDITY_TOKEN1);
        deal(address(dyson), bob, INITIAL_LIQUIDITY_TOKEN0);
    }

    function testDepositWithAgent() public {
        vm.startPrank(alice);
        IERC20(token0).approve(pair, type(uint).max);
        Pair(pair).deposit0(alice, 1e18, 900e18, 1 days);
        assertEq(Pair(pair).noteCount(alice), 1);
        uint output = Farm(farm).swap(alice);
        assertEq(dyson.balanceOf(alice), INITIAL_LIQUIDITY_TOKEN0 + output);
    }

    function testDepositWithoutAgent() public {
        vm.startPrank(bob);
        IERC20(token0).approve(pair, type(uint).max);
        Pair(pair).deposit0(bob, 1e18, 900e18, 1 days);
        assertEq(Pair(pair).noteCount(bob), 1);
        uint output = Farm(farm).swap(bob);
        assertEq(output, 0);
    }

    function testDepositWithAgentWithSDYSN() public {
        vm.startPrank(alice);
        dyson.approve(address(sdyson), type(uint).max);
        sdyson.stake(alice, 1000e18, 365.25 days);
        sdyson.approve(gauge, type(uint).max);
        Gauge(gauge).deposit(124e18, alice);
        assertGt(Gauge(gauge).bonus(alice), 0);
        IERC20(token0).approve(pair, type(uint).max);
        Pair(pair).deposit0(alice, 1e18, 900e18, 1 days);
        assertEq(Pair(pair).noteCount(alice), 1);
        uint output = Farm(farm).swap(alice);
        assertEq(dyson.balanceOf(alice), INITIAL_LIQUIDITY_TOKEN0 - 1000e18 + output);
    }

}