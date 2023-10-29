// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Pair.sol";
import "src/Factory.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";
import "src/Gauge.sol";
import "src/Agency.sol";
import "src/AgentNFT.sol";
import "src/Farm.sol";
import "src/Bribe.sol";
import "src/interface/IERC20.sol";
import "src/interface/IWETH.sol";
import "src/util/AddressBook.sol";
import "src/DysonToGo.sol";
import "./TestUtils.sol";
import "../lib/ABDKMath64x64.sol";

contract WETHMock is DYSON {
    constructor(address _owner) DYSON(_owner) {}

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint amount) public {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
}

contract DysonToGoTest is TestUtils {
    using ABDKMath64x64 for *;
    address testOwner = address(this);
    address public root = vm.addr(1);
    address WETH = address(new WETHMock(testOwner));
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    Factory factory = new Factory(testOwner);
    Pair normalPair = Pair(factory.createPair(token0, token1));
    Pair weth0Pair = Pair(factory.createPair(WETH, token1)); // WETH is token0
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address bribeToken = address(new DYSON(testOwner));
    address bribeToken2 = address(new DYSON(testOwner));
    
    AddressBook addressBook = new AddressBook(testOwner);
    Agency agency = new Agency(address(this), root);
    AgentNFT agentNft = agency.agentNFT();
    Farm farm = new Farm(testOwner, address(agency), address(gov));
    Gauge normalPairGauge = new Gauge(address(farm), sGov, address(normalPair), 10**24, 10**24, 10**24);
    Bribe bribe = new Bribe(address(normalPairGauge));
    Gauge weth0PairGauge = new Gauge(address(farm), sGov, address(weth0Pair), 10**24, 10**24, 10**24);
    DysonToGoFactory toGoFactory;
    DysonToGo toGo;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address zack = _nameToAddr("zack");
    address leader = _nameToAddr("leader");
    address briber = _nameToAddr("briber");

    uint constant INITIAL_WEALTH = 10**30;
    uint constant INITIAL_LIQUIDITY_TOKEN = 10**24;
    uint constant ADMIN_FEE_RATIO = 0.5e18; // set leader's admin fee ratio to 50%
    uint constant MAX_ADMIN_FEE_RATIO = 1e18;
    uint constant UPDATE_PERIOD = (1 + 1) * 6000; // farm swap CD = (gen + 1) * 6000
    uint constant PREMIUM_BASE_UNIT = 1e18;
    uint constant GLOBALRATE = 0.951e18;
    uint constant GLOBALWEIGHT = 821917e18;
    uint baseTimePassed = 1 weeks;

    function setUp() public {
        DYSON(gov).addMinter(address(farm));
        normalPair.setFarm(address(farm));
        weth0Pair.setFarm(address(farm));
        farm.setPool(address(normalPair), address(normalPairGauge));
        farm.setPool(address(weth0Pair), address(weth0PairGauge));
        farm.setGlobalRewardRate(GLOBALRATE, GLOBALWEIGHT);

        // make poolReserve grow up
        skip(baseTimePassed);

        addressBook.file("owner", testOwner);
        addressBook.file("govToken", gov);
        addressBook.file("govTokenStaking", sGov);
        addressBook.file("factory", address(factory));
        addressBook.file("farm", address(farm));
        addressBook.file("agentNFT", address(agency.agentNFT()));
        addressBook.file("agency", address(agency));
        addressBook.setBribeOfGauge(address(normalPairGauge), address(bribe));


        toGoFactory = new DysonToGoFactory(testOwner, WETH, address(addressBook));
        toGo = DysonToGo(payable(toGoFactory.createDysonToGo(leader)));
        // Owner make leader as tier1 agent.
        uint agentId = agency.adminAdd(leader);
        assertEq(agency.whois(leader), agentId);
        assertEq(agentNft.balanceOf(leader), 1);
        assertEq(agentNft.ownerOf(agentId), leader);
        (address ref, uint gen) = agency.userInfo(leader);
        assertEq(ref, root); // leader's parent is root.
        assertEq(gen, 1); // leader's generation is 1.

        // Make sure variable names are matched.
        assertEq(normalPair.token0(), token0);
        assertEq(normalPair.token1(), token1);
        assertEq(weth0Pair.token0(), WETH);
        assertEq(weth0Pair.token1(), token1);


        // Initialize token0 and token1 for pairs.
        deal(token0, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);

        // Initialize WETH for pairs.
        deal(zack, INITIAL_LIQUIDITY_TOKEN * 2);
        vm.startPrank(zack);
        IWETH(WETH).deposit{value: INITIAL_LIQUIDITY_TOKEN * 2}();
        IWETH(WETH).transfer(address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);
    
        // Initialize tokens and eth for handy accounts.
        deal(alice, INITIAL_WEALTH);
        deal(token0, alice, INITIAL_WEALTH);
        deal(token1, alice, INITIAL_WEALTH);
        deal(alice, INITIAL_WEALTH);
        deal(token0, bob, INITIAL_WEALTH);
        deal(token1, bob, INITIAL_WEALTH);
        deal(bob, INITIAL_WEALTH);
        deal(sGov, address(toGo), INITIAL_WEALTH);
        deal(sGov, bob, INITIAL_WEALTH);
        deal(bribeToken, briber, INITIAL_WEALTH);
        deal(bribeToken2, briber, INITIAL_WEALTH);

        // Appoving.
        changePrank(alice);
        IERC20(token0).approve(address(toGo), type(uint).max);
        IERC20(token1).approve(address(toGo), type(uint).max);
        changePrank(bob);
        IERC20(token0).approve(address(toGo), type(uint).max);
        IERC20(token1).approve(address(toGo), type(uint).max);
        sDYSON(sGov).approve(address(normalPairGauge), type(uint).max);
        changePrank(briber);
        DYSON(bribeToken).approve(address(bribe), type(uint).max);
        DYSON(bribeToken2).approve(address(bribe), type(uint).max);

        changePrank(leader);
        toGo.rely(sGov, address(normalPairGauge), true);
        toGo.rely(sGov, address(weth0PairGauge), true);
        toGo.rely(token0, address(normalPair), true);
        toGo.rely(token1, address(normalPair), true);
        toGo.rely(token1, address(weth0Pair), true);
        toGo.rely(WETH, address(weth0Pair), true);
        
        // leader transfer his NFT to toGo contract.
        agentNft.safeTransferFrom(leader, address(toGo), agentId);
        toGo.setAdminFeeRatio(ADMIN_FEE_RATIO);
        toGo.setUpdatePeriod(UPDATE_PERIOD);
        vm.stopPrank();

        assertEq(agentNft.balanceOf(address(toGo)), 1);
        assertEq(agentNft.ownerOf(agentId), address(toGo));
        assertEq(toGo.adminFeeRatio(), ADMIN_FEE_RATIO);
        assertEq(toGo.updatePeriod(), UPDATE_PERIOD);
    }

    function testCreateDysonToGo() public {
        address payable dysonToGo = payable(toGoFactory.createDysonToGo(alice));
        assertEq(DysonToGo(dysonToGo).owner(), alice);
        assertEq(DysonToGo(dysonToGo).WETH(), WETH);
        assertEq(DysonToGo(dysonToGo).ADDRESS_BOOK(), address(addressBook));
        assertEq(toGoFactory.allInstancesLength(), 2);
        assertEq(toGoFactory.allInstances(0), address(toGo));
        assertEq(toGoFactory.allInstances(1), dysonToGo);

        for(uint i = 2; i <= 20; ++i) {
            dysonToGo = payable(toGoFactory.createDysonToGo(alice));
            assertEq(toGoFactory.allInstancesLength(), i + 1);
            assertEq(toGoFactory.allInstances(i), dysonToGo);
        }   
    }

    function testCannotCreateDysonToGoByNonController() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        toGoFactory.createDysonToGo(alice);

        toGoFactory.addController(alice);
        assertEq(toGoFactory.isController(alice), true);
        vm.prank(alice);
        address payable dysonToGo = payable(toGoFactory.createDysonToGo(alice));
        assertEq(DysonToGo(dysonToGo).owner(), alice);

        toGoFactory.removeController(alice);
        assertEq(toGoFactory.isController(alice), false);
        vm.prank(alice);
        vm.expectRevert("forbidden");
        toGoFactory.createDysonToGo(alice);
    }

    function testCannotSetAdminFeeRatioExceedMax() public {
        vm.startPrank(leader);
        vm.expectRevert("invalid admin fee ratio");
        toGo.setAdminFeeRatio(MAX_ADMIN_FEE_RATIO + 1);
    }

    function testGaugeDeposit() public {
        uint genesis = normalPairGauge.genesis() + 1;   // baseTimePassed = 1 week
        vm.startPrank(leader);

        // Week Balance
        //  0      1
        //  1      4
        //  3      9
        toGo.gaugeDeposit(address(normalPairGauge), 1);
        skip(1 weeks);
        toGo.gaugeDeposit(address(normalPairGauge), 3);
        skip(2 weeks);
        toGo.gaugeDeposit(address(normalPairGauge), 5);
        skip(1 weeks);
        normalPairGauge.tick();
        vm.stopPrank();

        assertEq(normalPairGauge.balanceOfAt(address(toGo), genesis), 1);
        assertEq(normalPairGauge.balanceOfAt(address(toGo), 1 + genesis), 4);
        assertEq(normalPairGauge.balanceOfAt(address(toGo), 2 + genesis), 4);
        assertEq(normalPairGauge.balanceOfAt(address(toGo), 3 + genesis), 9);
        assertEq(normalPairGauge.balanceOf(address(toGo)), 9);

        assertEq(normalPairGauge.totalSupplyAt(genesis), 1);
        assertEq(normalPairGauge.totalSupplyAt(1 + genesis), 4);
        assertEq(normalPairGauge.totalSupplyAt(2 + genesis), 4);
        assertEq(normalPairGauge.totalSupplyAt(3 + genesis), 9);
        assertEq(normalPairGauge.totalSupply(), 9);
    }

    function testGaugeWithdraw() public {
        uint depositAmount = 10;
        uint withdrawAmount = 6;
        vm.startPrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), depositAmount);

        uint sGovBalanceBefore = IERC20(sGov).balanceOf(address(toGo));
        toGo.gaugeApplyWithdrawal(address(normalPairGauge), withdrawAmount);
        assertEq(normalPairGauge.balanceOf(address(toGo)), depositAmount - withdrawAmount);
        assertEq(normalPairGauge.totalSupply(), depositAmount - withdrawAmount);
        assertEq(IERC20(sGov).balanceOf(address(toGo)), sGovBalanceBefore);

        skip(1 weeks);
        toGo.gaugeWithdraw(address(normalPairGauge));
        uint sGovBalanceAfter = IERC20(sGov).balanceOf(address(toGo));
        assertEq(sGovBalanceAfter - sGovBalanceBefore, withdrawAmount);
    }

    function testBribeClaimReward() public {
        uint bribeAmount = 100;
        uint bribeWeek = normalPairGauge.genesis() + 1; // baseTimePassed = 1 week
        vm.startPrank(briber);
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 1, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 2, bribeAmount);

        // Week  toGo  Bob  TotalSupply  Bribe
        //  0      1     0         1       100
        //  1      1     3         4       100
        //  2      3     7        10       100
        //  thisWeek = 3
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 1);
        skip(1 weeks);
        changePrank(bob);
        normalPairGauge.deposit(3, bob);
        skip(1 weeks);
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 2);
        changePrank(bob);
        normalPairGauge.deposit(4, bob);
        skip(1 weeks);
        normalPairGauge.tick();

        // leader claim week2 reward
        uint[] memory week = new uint[](1);
        week[0] = bribeWeek + 2;
        uint leaderReward = 100*3/10;
        
        changePrank(leader);
        assertEq(toGo.bribeClaimRewards(address(normalPairGauge), bribeToken, week), leaderReward);
        assertEq(DYSON(bribeToken).balanceOf(leader), leaderReward);
    }
    
    function testBribeClaimRewards() public {
        uint bribeAmount = 100;
        uint bribeWeek = normalPairGauge.genesis() + 1; // baseTimePassed = 1 week
        vm.startPrank(briber);
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 1, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 2, bribeAmount);

        // Week  toGo  Bob  TotalSupply  Bribe
        //  0      1     0         1       100
        //  1      1     3         4       100
        //  2      3     7        10       100
        //  thisWeek = 3
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 1);
        skip(1 weeks);
        changePrank(bob);
        normalPairGauge.deposit(3, bob);
        skip(1 weeks);
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 2);
        changePrank(bob);
        normalPairGauge.deposit(4, bob);
        skip(1 weeks);
        normalPairGauge.tick();

        uint[] memory week = new uint[](3);
        week[0] = bribeWeek;
        week[1] = bribeWeek + 1;
        week[2] = bribeWeek + 2;
        uint leaderTotalReward = 100*1 + 100*1/4 + 100*3/10;
        
        changePrank(leader);
        assertEq(toGo.bribeClaimRewards(address(normalPairGauge), bribeToken, week), leaderTotalReward);
        assertEq(DYSON(bribeToken).balanceOf(leader), leaderTotalReward);
    }

    function testBribeClaimMultipleTokens() public {
        uint bribeAmount = 100;
        uint bribe2Amount = 200;
        uint bribeWeek = normalPairGauge.genesis() + 1; // baseTimePassed = 1 week

        // add reward for bribeToken and bribeToken2
        vm.startPrank(briber);
        bribe.addReward(bribeToken, bribeWeek, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 1, bribeAmount);
        bribe.addReward(bribeToken, bribeWeek + 2, bribeAmount);
        bribe.addReward(bribeToken2, bribeWeek, bribe2Amount);
        bribe.addReward(bribeToken2, bribeWeek + 1, bribe2Amount);
        bribe.addReward(bribeToken2, bribeWeek + 2, bribe2Amount);

        // Week  toGo  Bob  TotalSupply  BribeToken  BribeToken2
        //  0      1     0         1       100          200
        //  1      1     3         4       100          200
        //  2      3     7        10       100          200
        //  thisWeek = 3
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 1);
        skip(1 weeks);
        changePrank(bob);
        normalPairGauge.deposit(3, bob);
        skip(1 weeks);
        changePrank(leader);
        toGo.gaugeDeposit(address(normalPairGauge), 2);
        changePrank(bob);
        normalPairGauge.deposit(4, bob);
        skip(1 weeks);
        normalPairGauge.tick();

        uint[][] memory week = new uint[][](2);
        for(uint i=0; i<2; i++) {
            week[i] = new uint[](3);
            week[i][0] = bribeWeek;
            week[i][1] = bribeWeek + 1;
            week[i][2] = bribeWeek + 2;
        }

        address[] memory tokens = new address[](2);
        tokens[0] = bribeToken;
        tokens[1] = bribeToken2;
        uint leaderBribeTokenReward = 100*1 + 100*1/4 + 100*3/10;
        uint leaderBribeToken2Reward = 200*1 + 200*1/4 + 200*3/10;
        
        changePrank(leader);
        uint[] memory amounts = toGo.bribeClaimRewardsMultipleTokens(address(normalPairGauge), tokens, week);
        assertEq(amounts[0], leaderBribeTokenReward);
        assertEq(amounts[1], leaderBribeToken2Reward);
        assertEq(DYSON(bribeToken).balanceOf(leader), leaderBribeTokenReward);
        assertEq(DYSON(bribeToken2).balanceOf(leader), leaderBribeToken2Reward);
    }

    function testAdminWithdrawSdyson() public {
        uint amount = 100;
        vm.startPrank(leader);
        toGo.adminWithdrawSdyson(amount);
        assertEq(DYSON(sGov).balanceOf(leader), amount);
    }

    function testAdminWithdrawAgent() public {
        uint transferCD = (1 + 1) * 60000 + 1;
        skip(transferCD);

        uint agentId = agency.whois(address(toGo));
        vm.startPrank(leader);
        toGo.adminWithdrawAgent(agentId);

        assertEq(agentNft.balanceOf(address(toGo)), 0);
        assertEq(agentNft.balanceOf(leader), 1);
        assertEq(agentNft.ownerOf(agentId), leader);
        assertEq(agency.whois(address(toGo)), 0);
        assertEq(agency.whois(leader), agentId);
    }

    function testUpdate() public {
        // dysonPool, spPool, spInFarm should be 0 at the beginning
        uint spInFarm = toGo.update();
        assertEq(toGo.dysonPool(), 0);
        assertEq(toGo.spPool(), 0);
        assertEq(spInFarm, 0);

        // first deposit
        vm.prank(alice);
        toGo.deposit(token0, token1, 1, 10**18, 0, 1 days);

        // dysonPool, spPool should remain 0 after first deposit, but spInFarm should be increased
        spInFarm = toGo.update();
        assertEq(toGo.dysonPool(), 0);
        assertEq(toGo.spPool(), 0);
        assertEq(spInFarm, farm.balanceOf(address(toGo)));
        // spPending is toGo's SP balance in Farm which can be swapped to DYSON upon swapCD is cool down
        uint spPending = toGo.spPending();

        skip(UPDATE_PERIOD + 1);
        // This time, toGo's SP in Farm will be swapped to DYSON
        uint farmGlobalReserve = farm.getCurrentGlobalReserve();
        spInFarm = toGo.update();

        // calculate the amount of DYSON swapped from SP
        uint dysonAddedInToGo = _calcRewardAmount(farmGlobalReserve, spPending, GLOBALWEIGHT);
        // calculate the DYSON amount which leader and toGo supposed to get
        uint adminFee = dysonAddedInToGo * ADMIN_FEE_RATIO / MAX_ADMIN_FEE_RATIO;
        uint toGoIncome = dysonAddedInToGo - adminFee;

        uint toGoBalance = DYSON(gov).balanceOf(address(toGo));
        uint leaderBalance = DYSON(gov).balanceOf(leader);
        assertEq(toGoBalance, 0 + toGoIncome);
        assertEq(leaderBalance, 0 + adminFee);
        assertEq(toGo.spPool(), 0 + spPending);
        assertEq(spInFarm, 0);
        
        // second deposit
        vm.prank(alice);
        toGo.deposit(token0, token1, 1, 10**18, 0, 1 days);

        uint toGoDysonPoolBefore = toGo.dysonPool();
        uint toGoSpPoolBefore = toGo.spPool();
        uint leaderBalanceBefore = DYSON(gov).balanceOf(leader);
        spPending = toGo.spPending();

        skip(UPDATE_PERIOD + 1);
        farmGlobalReserve = farm.getCurrentGlobalReserve();
        spInFarm = toGo.update();

        dysonAddedInToGo = _calcRewardAmount(farmGlobalReserve, spPending, GLOBALWEIGHT);
        adminFee = dysonAddedInToGo * ADMIN_FEE_RATIO / MAX_ADMIN_FEE_RATIO;
        toGoIncome = dysonAddedInToGo - adminFee;

        toGoBalance = DYSON(gov).balanceOf(address(toGo));
        leaderBalance = DYSON(gov).balanceOf(leader);
        assertEq(toGoBalance, toGoDysonPoolBefore + toGoIncome);
        assertEq(leaderBalance, leaderBalanceBefore + adminFee);
        assertEq(toGo.spPool(), toGoSpPoolBefore + spPending);
        assertEq(spInFarm, 0);
    }

    function testDeposit() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint spBefore = toGo.update();
        uint noteCount = normalPair.noteCount(address(toGo));
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = normalPair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = toGo.deposit(token0, token1, 1, depositAmount, 0, period);

        // check toGo contract's position in pair
        (uint token0Amt, uint token1Amt, uint due) = normalPair.notes(address(toGo), 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);

        // check alice's position in toGo contract
        (uint index, uint spAmount, bool hasDepositedAsset) = toGo.positions(address(normalPair), alice, 0);
        uint spAfter = farm.balanceOf(address(toGo));
        uint spAdded = spAfter - spBefore;
        assertEq(index, noteCount);
        assertEq(spAmount, spAdded);
        assertEq(hasDepositedAsset, true);
    }

    function testDepositETH() public {
        uint oldBalance = alice.balance;
        uint spBefore = toGo.update();
        uint noteCount = weth0Pair.noteCount(address(toGo));
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = weth0Pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = toGo.depositETH{value: depositAmount}(token1, 1, 0, period);

        // check toGo contract's position in pair
        (uint wethAmount, uint token1Amt, uint due) = weth0Pair.notes(address(toGo), 0);
        assertEq(wethAmount, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        uint newBalance = alice.balance;
        assertEq(newBalance, oldBalance - depositAmount);

        // check alice's position in toGo contract
        (uint index, uint spAmount, bool hasDepositedAsset) = toGo.positions(address(weth0Pair), alice, 0);
        uint spAfter = farm.balanceOf(address(toGo));
        uint spAdded = spAfter - spBefore;
        assertEq(index, noteCount);
        assertEq(spAmount, spAdded);
        assertEq(hasDepositedAsset, true);
    }

    function testWithdraw() public {
        uint depositAmount = 10**18;
        uint period = 1 days;

        vm.startPrank(alice);
        toGo.deposit(token0, token1, 1, depositAmount, 0, period);

        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);

        skip(period + 1);
        toGo.update();
        // Get updated spPool and dysonPool, and calculate alice's dyson income after withdrawal
        uint spPool = toGo.spPool();
        uint dysonPool = toGo.dysonPool();
        (, uint spAmount,) = toGo.positions(address(normalPair), alice, 0);
        uint aliceDysonIncome = dysonPool * spAmount / (spPool + spAmount);

        // alice withdraw 
        (uint token0Amt, uint token1Amt, uint dysonAmt) = toGo.withdraw(address(normalPair), 0, alice);
        vm.stopPrank();

        (,, bool hasDepositedAsset) = toGo.positions(address(normalPair), alice, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(hasDepositedAsset, false);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
        assertEq(aliceDysonIncome, dysonAmt);
        assertEq(toGo.spPool(), spPool - spAmount);
        assertEq(toGo.dysonPool(), dysonPool - dysonAmt);
    }

    function testCannotWithdrawTwice() public {
        uint depositAmount = 10**18;
        uint period = 1 days;

        vm.startPrank(alice);
        toGo.deposit(token0, token1, 1, depositAmount, 0, period);

        skip(period + 1);
        toGo.withdraw(address(normalPair), 0, alice);
        vm.expectRevert("not deposited");
        toGo.withdraw(address(normalPair), 0, alice);
    }

    function testWithdrawETH() public {
        uint depositAmount = 10**18;
        uint period = 1 days;

        vm.startPrank(alice);
        toGo.depositETH{value: depositAmount}(token1, 1, 0, period);

        uint oldETHBalance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);

        skip(period + 1);
        toGo.update();
        // Get updated spPool and dysonPool, and calculate alice's dyson income after withdrawal
        uint spPool = toGo.spPool();
        uint dysonPool = toGo.dysonPool();
        (, uint spAmount,) = toGo.positions(address(weth0Pair), alice, 0);
        uint aliceDysonIncome = dysonPool * spAmount / (spPool + spAmount);

        (uint token0Amt, uint token1Amt, uint dysonAmt) = toGo.withdrawETH(address(weth0Pair), 0, alice);
        vm.stopPrank();

        (,, bool hasDepositedAsset) = toGo.positions(address(normalPair), alice, 0);
        uint newETHBalance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(hasDepositedAsset, false);
        assertEq(newETHBalance, oldETHBalance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
        assertEq(aliceDysonIncome, dysonAmt);
        assertEq(toGo.spPool(), spPool - spAmount);
        assertEq(toGo.dysonPool(), dysonPool - dysonAmt);
    }

    // as a contract wallet, toGo need to presign to Agency.sol
    function testRegisterNewAgentFromToGo() public {
        bytes32 REGISTER_ONCE_TYPEHASH = keccak256("register(address child)"); // onceSig
        bytes32 REGISTER_PARENT_TYPEHASH = keccak256("register(address once,uint256 deadline,uint256 price)"); // parentSig
        bytes32 DOMAIN_SEPARATOR = agency.DOMAIN_SEPARATOR();
        uint REGISTER_DELAY = 4 hours;
        uint onceKey = 66666;
        address onceAddr = vm.addr(onceKey);
        uint deadline = block.timestamp + 1 days;
        address newAgent = vm.addr(5);

        // parent sign parentSig
        bytes32 parentDigest = _getHashTypedData(
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                REGISTER_PARENT_TYPEHASH,
                onceAddr,
                deadline,
                0
            )
        ));

        // child sign onceSig
        bytes32 childDigest = _getHashTypedData(
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                REGISTER_ONCE_TYPEHASH,
                newAgent
            )
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(onceKey, childDigest);
        bytes memory onceSig = abi.encodePacked(r, s, v);

        // toGo presign to Agency.sol
        vm.prank(leader);
        toGo.sign(parentDigest);
        
        bytes memory parentAddress = abi.encodePacked(address(toGo));

        // child call register
        skip(REGISTER_DELAY + 1);
        vm.prank(newAgent);
        uint agentId = agency.register(parentAddress, onceSig, deadline);

        assertEq(agency.whois(newAgent), 3);
        assertEq(agentNft.balanceOf(newAgent), 1);
        assertEq(agentNft.ownerOf(agentId), newAgent);
    }

    function _getHashTypedData(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // Duplication from Farm.sol
    function _calcRewardAmount(uint _reserve, uint _amount, uint _w) internal pure returns (uint reward) {
        int128 r = _amount.divu(_w);
        int128 e = (-r).exp_2();
        reward = (2**64 - e).mulu(_reserve);
    }

}