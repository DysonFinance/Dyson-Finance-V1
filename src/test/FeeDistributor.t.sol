// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Pair.sol";
import "src/Factory.sol";
import "src/GaugeFactory.sol";
import "src/BribeFactory.sol";
import "src/DYSON.sol";
import "src/Bribe.sol";
import "util/FeeDistributor.sol";
import "src/sDYSON.sol";
import "src/Gauge.sol";
import "./TestUtils.sol";

contract FarmMock {}

contract FeeDistributorTest is TestUtils {
    address testOwner = address(this);
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    Factory factory = new Factory(testOwner);
    GaugeFactory gaugeFactory = new GaugeFactory(testOwner);
    BribeFactory bribeFactory = new BribeFactory(testOwner);
    Pair pair = Pair(factory.createPair(token0, token1));

    uint constant INITIAL_WEIGHT = 10**24;
    uint constant INITIAL_BASE = 10**24;
    uint constant INITIAL_SLOPE = 10**24;

    uint immutable INITIAL_LIQUIDITY_TOKEN0 = 1000000e18;
    uint immutable INITIAL_LIQUIDITY_TOKEN1 = 100e18;
    uint immutable INITIAL_WEALTH = 1e30;
    uint feeRateToDao = 0.6e18;

    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address farm = address(new FarmMock());
    
    Gauge gauge = Gauge(gaugeFactory.createGauge(farm, sGov, address(pair), INITIAL_WEIGHT, INITIAL_BASE, INITIAL_SLOPE));
    Bribe bribe = Bribe(bribeFactory.createBribe(address(gauge)));

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address briber = _nameToAddr("briber");
    address daoWallet = _nameToAddr("daoWallet");

    FeeDistributor feeDistributor = new FeeDistributor(testOwner, address(pair), address(bribe), daoWallet, feeRateToDao);

    function setUp() public {
        // Initialize liquidity of Pair.
        deal(token0, address(pair), INITIAL_LIQUIDITY_TOKEN0);
        deal(token1, address(pair), INITIAL_LIQUIDITY_TOKEN1);

        deal(sGov, alice, INITIAL_WEALTH);
        deal(sGov, bob, INITIAL_WEALTH);
        vm.prank(alice);
        sDYSON(sGov).approve(address(gauge), INITIAL_WEALTH);
        vm.prank(bob);
        sDYSON(sGov).approve(address(gauge), INITIAL_WEALTH);

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

        pair.setFeeTo(address(feeDistributor));
    }

    function testDistributeFee() public {

        // User deposit to pair
        vm.startPrank(alice);
        for(uint i = 0; i < 2; i++) {
            pair.deposit0(alice, 10000e18, 0, 1 days);
            pair.deposit1(alice, 100e18, 0, 1 days);
        }
        
        changePrank(bob);
        for(uint i = 0; i < 2; i++) {
            pair.deposit0(bob, 10000e18, 0, 1 days);
            pair.deposit1(bob, 100e18, 0, 1 days);
        }
        vm.stopPrank();

        uint genesisWeek = gauge.genesis();

        // pair send accumulated fee to FeeDistributor
        pair.collectFee();
        uint token0BalanceOfFeeDistributor = IERC20(token0).balanceOf(address(feeDistributor));
        uint token1BalanceOfFeeDistributor = IERC20(token1).balanceOf(address(feeDistributor));
        uint token0FeeToDAO = token0BalanceOfFeeDistributor * feeRateToDao / 1e18;
        uint token1FeeToDAO = token1BalanceOfFeeDistributor * feeRateToDao / 1e18;
        uint token0FeeToBribe = token0BalanceOfFeeDistributor - token0FeeToDAO;
        uint token1FeeToBribe = token1BalanceOfFeeDistributor - token1FeeToDAO;

        // FeeDistributor send fee to DAO wallet and bribe
        feeDistributor.distributeFee();
        assertEq(IERC20(token0).balanceOf(address(daoWallet)), token0FeeToDAO);
        assertEq(IERC20(token1).balanceOf(address(daoWallet)), token1FeeToDAO);
        assertEq(bribe.tokenRewardOfWeek(token0, genesisWeek), 0);
        assertEq(bribe.tokenRewardOfWeek(token1, genesisWeek), 0);
        assertEq(bribe.tokenRewardOfWeek(token0, genesisWeek + 1), token0FeeToBribe);
        assertEq(bribe.tokenRewardOfWeek(token1, genesisWeek + 1), token1FeeToBribe);
        assertEq(IERC20(token0).balanceOf(address(bribe)), token0FeeToBribe);
        assertEq(IERC20(token1).balanceOf(address(bribe)), token1FeeToBribe);
    }

}