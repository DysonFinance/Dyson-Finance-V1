// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/Pair.sol";
import "src/Factory.sol";
import "src/GaugeFactory.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";
import "src/Gauge.sol";
import "src/Router.sol";
import "src/interface/IERC20.sol";
import "src/interface/IWETH.sol";
import "./TestUtils.sol";

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
contract MockContract {}

contract RouterTest is TestUtils {
    address testOwner = address(this);
    address WETH = address(new WETHMock(testOwner));
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    address token2 = address(new DYSON(testOwner));
    address token3 = address(new DYSON(testOwner));
    Factory factory = new Factory(testOwner);
    GaugeFactory gaugeFactory = new GaugeFactory(testOwner);
    Pair normalPair = Pair(factory.createPair(token0, token1));
    Pair normalPair2 = Pair(factory.createPair(token2, token3));
    Pair normalPair3 = Pair(factory.createPair(token1, token2));
    Pair weth0Pair = Pair(factory.createPair(WETH, token1)); // WETH is token0
    Pair weth1Pair = Pair(factory.createPair(token0, WETH)); // WETH is token1
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    Gauge gauge = Gauge(gaugeFactory.createGauge(address(new MockContract()), sGov, address(0), 10**24, 10**24, 10**24));
    Router router = new Router(WETH, testOwner, address(factory), sGov, gov);

    bytes32 constant APPROVE_TYPEHASH = keccak256("setApprovalForAllWithSig(address owner,address operator,bool approved,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    uint constant PREMIUM_BASE_UNIT = 1e18;
    uint constant INITIAL_LIQUIDITY_TOKEN = 10**24;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    address zack = _nameToAddr("zack");
    uint constant INITIAL_WEALTH = 10**30;

    struct Note {
        uint token0Amt;
        uint token1Amt;
        uint due;
    }

    function setUp() public {
        // Make sure variable names are matched.
        assertEq(normalPair.token0(), token0);
        assertEq(normalPair.token1(), token1);
        assertEq(normalPair2.token0(), token2);
        assertEq(normalPair2.token1(), token3);
        assertEq(normalPair3.token0(), token2);
        assertEq(normalPair3.token1(), token1);
        assertEq(weth0Pair.token0(), WETH);
        assertEq(weth0Pair.token1(), token1);
        assertEq(weth1Pair.token0(), token0);
        assertEq(weth1Pair.token1(), WETH);

        // Initialize token0 and token1 for pairs.
        deal(token0, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(normalPair), INITIAL_LIQUIDITY_TOKEN);
        deal(token2, address(normalPair2), INITIAL_LIQUIDITY_TOKEN);
        deal(token3, address(normalPair2), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(normalPair3), INITIAL_LIQUIDITY_TOKEN);
        deal(token2, address(normalPair3), INITIAL_LIQUIDITY_TOKEN);
        deal(token1, address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);
        deal(token0, address(weth1Pair), INITIAL_LIQUIDITY_TOKEN);

        router.rely(token0, address(normalPair), true);
        router.rely(token1, address(normalPair), true);
        router.rely(token2, address(normalPair2), true);
        router.rely(token3, address(normalPair2), true);
        router.rely(token1, address(normalPair3), true);
        router.rely(token2, address(normalPair3), true);
        router.rely(token0, address(weth1Pair), true);
        router.rely(token1, address(weth0Pair), true);
        router.rely(WETH, address(weth0Pair), true);
        router.rely(WETH, address(weth1Pair), true);
        router.rely(sGov, address(gauge), true);
        router.rely(gov, address(sGov), true);


        // Initialize WETH for pairs.
        deal(zack, INITIAL_LIQUIDITY_TOKEN * 2);
        vm.startPrank(zack);
        IWETH(WETH).deposit{value: INITIAL_LIQUIDITY_TOKEN * 2}();
        IWETH(WETH).transfer(address(weth0Pair), INITIAL_LIQUIDITY_TOKEN);
        IWETH(WETH).transfer(address(weth1Pair), INITIAL_LIQUIDITY_TOKEN);
    
        // Initialize tokens and eth for handy accounts.
        deal(token0, alice, INITIAL_WEALTH);
        deal(token1, alice, INITIAL_WEALTH);
        deal(token2, alice, INITIAL_WEALTH);
        deal(token3, alice, INITIAL_WEALTH);
        deal(alice, INITIAL_WEALTH);
        deal(token0, bob, INITIAL_WEALTH);
        deal(token1, bob, INITIAL_WEALTH);
        deal(bob, INITIAL_WEALTH);

        // Appoving.
        changePrank(alice);
        IERC20(token0).approve(address(router), type(uint).max);
        IERC20(token1).approve(address(router), type(uint).max);
        IERC20(token2).approve(address(router), type(uint).max);
        IERC20(token3).approve(address(router), type(uint).max);
        changePrank(bob);
        IERC20(token0).approve(address(router), type(uint).max);
        IERC20(token1).approve(address(router), type(uint).max);
        vm.stopPrank();

        // Labeling.
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(address(router), "Router");
        vm.label(address(normalPair), "Normal Pair");
        vm.label(address(weth0Pair), "WETH0 Pair");
        vm.label(address(weth1Pair), "WETH1 Pair");
        vm.label(token0, "Token 0");
        vm.label(token1, "Token 1");
        vm.label(WETH, "WETH");
    }

    function testNormalPairSwap01() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swap(token0, token1, 1, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swap(token1, token0, 1, alice, output1, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testNormalPairSwap10() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swap(token1, token0, 1, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swap(token0, token1, 1, alice, output0, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testWeth0PairSwap01() public {
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swapETHIn{value: swapAmount}(token1, 1, alice, 0);
        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swapETHOut(token1, 1, alice, output1, 0);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testWeth0PairSwap10() public {
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swapETHOut(token1, 1, alice, swapAmount, 0);
        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swapETHIn{value: output0}(token1, 1, alice, 0);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testWeth1PairSwap01() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output1 = router.swapETHOut(token0, 1, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken1Balance, oldToken1Balance + output1);

        output0 = router.swapETHIn{value: output1}(token0, 1, alice, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - swapAmount + output0);
        assertEq(newToken1Balance, oldToken1Balance);
        assertTrue(output0 <= swapAmount);
    }

    function testWeth1PairSwap10() public {
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        uint swapAmount = 10**18;
        uint output0; 
        uint output1;

        vm.startPrank(alice);
        output0 = router.swapETHIn{value: swapAmount}(token0, 1, alice, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount);

        output1 = router.swapETHOut(token0, 1, alice, output0, 0);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance);
        assertEq(newToken1Balance, oldToken1Balance - swapAmount + output1);
        assertTrue(output1 <= swapAmount);
    }

    function testNormalPairDeposit() public {
        Pair pair = normalPair;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        uint output0 = router.deposit(token1, token0, 1, alice, depositAmount, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testWeth0Deposit() public {
        Pair pair = weth0Pair;
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.depositETH{value: depositAmount}(token1, 1, alice, 0, period);
        uint output0 = router.deposit(token1, WETH, 1, alice, depositAmount, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testWeth1Deposit() public {
        Pair pair = weth1Pair;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        vm.startPrank(alice);
        uint output1 = router.deposit(token0, WETH, 1, alice, depositAmount, 0, period);
        uint output0 = router.depositETH{value: depositAmount}(token0, 1, alice, 0, period);

        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);
        
        (token0Amt, token1Amt, due) = pair.notes(alice, 1);
        assertEq(token0Amt, output0 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
        assertEq(newToken1Balance, oldToken1Balance - depositAmount);
    }

    function testNormalPairWithdraw() public {
        Pair pair = normalPair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        router.deposit(token1, token0, 1, alice, depositAmount, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        bytes memory sig = _getApprovalSig(address(pair), _nameToKey("alice"), true, deadline);
        router.setApprovalForAllWithSig(address(pair), true, deadline, sig);
        (uint token0Amt, uint token1Amt) = router.withdraw(address(pair), index, alice);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = IERC20(token0).balanceOf(alice);
        oldToken1Balance = IERC20(token1).balanceOf(alice);
        (token0Amt, token1Amt) = router.withdraw(address(pair), index, alice);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testNormalPairWithdrawThroughUserDirectlyApprove() public {
        Pair pair = normalPair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        router.deposit(token1, token0, 1, alice, depositAmount, 0, period);
        skip(period);

        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        pair.setApprovalForAll(address(router), true);
        (uint token0Amt, uint token1Amt) = router.withdraw(address(pair), index, alice);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = IERC20(token0).balanceOf(alice);
        oldToken1Balance = IERC20(token1).balanceOf(alice);
        (token0Amt, token1Amt) = router.withdraw(address(pair), index, alice);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }
    function testNormalPairWithdrawMultiPositions() public {
        Pair pair = normalPair;
        Pair pair2 = normalPair2;
        uint depositAmount = 10**18;
        uint period = 1 days;

        vm.startPrank(alice);
        router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        router.deposit(token1, token0, 1, alice, depositAmount, 0, period);
        router.deposit(token2, token3, 1, alice, depositAmount, 0, period);
        router.deposit(token3, token2, 1, alice, depositAmount, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint[] memory oldTokenBalances = new uint[](4);
        oldTokenBalances[0] = IERC20(token0).balanceOf(alice);
        oldTokenBalances[1] = IERC20(token1).balanceOf(alice);
        oldTokenBalances[2] = IERC20(token2).balanceOf(alice);
        oldTokenBalances[3] = IERC20(token3).balanceOf(alice);
        
        bytes memory sig = _getApprovalSig(address(pair), _nameToKey("alice"), true, deadline);
        bytes memory sig2 = _getApprovalSig(address(pair2), _nameToKey("alice"), true, deadline);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(Router.setApprovalForAllWithSig.selector, address(pair), true, deadline, sig);
        data[1] = abi.encodeWithSelector(Router.setApprovalForAllWithSig.selector, address(pair2), true, deadline, sig2);
        
        // set approval for all pools
        router.multicall(data);        

        address[] memory pairs = new address[](4);
        pairs[0] = address(pair);
        pairs[1] = address(pair);
        pairs[2] = address(pair2);
        pairs[3] = address(pair2);

        uint[] memory indexes = new uint[](4);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 0;
        indexes[3] = 1;

        address[] memory tos = new address[](4);
        for(uint i=0; i < 4; i++) {
            tos[i] = alice;
        }

        (uint[] memory token0Amounts, uint[] memory token1Amounts) = router.withdrawMultiPositions(pairs, indexes, tos);

        uint[] memory newTokenBalances = new uint[](4);
        newTokenBalances[0] = IERC20(token0).balanceOf(alice);
        newTokenBalances[1] = IERC20(token1).balanceOf(alice);
        newTokenBalances[2] = IERC20(token2).balanceOf(alice);
        newTokenBalances[3] = IERC20(token3).balanceOf(alice);

        assertEq(newTokenBalances[0], oldTokenBalances[0] + token0Amounts[0] + token0Amounts[1]);
        assertEq(newTokenBalances[1], oldTokenBalances[1] + token1Amounts[0] + token1Amounts[1]);
        assertEq(newTokenBalances[2], oldTokenBalances[2] + token0Amounts[2] + token0Amounts[3]);
        assertEq(newTokenBalances[3], oldTokenBalances[3] + token1Amounts[2] + token1Amounts[3]);
    }

    function testWeth0WithdrawETH() public {
        Pair pair = weth0Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;


        vm.startPrank(alice);
        router.depositETH{value: depositAmount}(token1, 1, alice, 0, period);
        router.deposit(token1, WETH, 1, alice, depositAmount, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = alice.balance;
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        bytes memory sig = _getApprovalSig(address(pair), _nameToKey("alice"), true, deadline);
        router.setApprovalForAllWithSig(address(pair), true, deadline, sig);
        (uint token0Amt, uint token1Amt) = router.withdrawETH(address(pair), index, alice);

        uint newToken0Balance = alice.balance;
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = alice.balance;
        oldToken1Balance = IERC20(token1).balanceOf(alice);
        (token0Amt, token1Amt) = router.withdrawETH(address(pair), index, alice);
        newToken0Balance = alice.balance;
        newToken1Balance = IERC20(token1).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testWeth1WithdrawETH() public {
        Pair pair = weth1Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit(token0, WETH, 1, alice, depositAmount, 0, period);
        router.depositETH{value: depositAmount}(token0, 1, alice, 0, period);
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = alice.balance;
        bytes memory sig = _getApprovalSig(address(pair), _nameToKey("alice"), true, deadline);
        router.setApprovalForAllWithSig(address(pair), true, deadline, sig);
        (uint token0Amt, uint token1Amt) = router.withdrawETH(address(pair), index, alice);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);

        index = index + 1;
        oldToken0Balance = IERC20(token0).balanceOf(alice);
        oldToken1Balance = alice.balance;
        (token0Amt, token1Amt) = router.withdrawETH(address(pair), index, alice);
        newToken0Balance = IERC20(token0).balanceOf(alice);
        newToken1Balance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + token0Amt);
        assertEq(newToken1Balance, oldToken1Balance + token1Amt);
    }

    function testCannotSetApprovalWithNotSelfSignedSig() public {
        uint deadline = block.timestamp + 1;
        bool approved = true;

        // sender == bob
        // signer == alice
        vm.startPrank(bob);
        bytes memory sig = _getApprovalSig(address(normalPair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("invalid signature");
        router.setApprovalForAllWithSig(address(normalPair), approved, deadline, sig);

        sig = _getApprovalSig(address(weth0Pair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("invalid signature");
        router.setApprovalForAllWithSig(address(weth0Pair), approved, deadline, sig);
        

        sig = _getApprovalSig(address(weth1Pair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("invalid signature");
        router.setApprovalForAllWithSig(address(weth1Pair), approved, deadline, sig);        
    }

    function testCannotSetApprovalWithExpiredSig() public {
        uint deadline = block.timestamp + 1;
        skip(2);
        bool approved = true;

        // sender == signer == alice
        vm.startPrank(alice);
        bytes memory sig = _getApprovalSig(address(normalPair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("exceed deadline");
        router.setApprovalForAllWithSig(address(normalPair), approved, deadline, sig);

        sig = _getApprovalSig(address(weth0Pair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("exceed deadline");
        router.setApprovalForAllWithSig(address(weth0Pair), approved, deadline, sig);

        sig = _getApprovalSig(address(weth1Pair), _nameToKey("alice"), approved, deadline);
        vm.expectRevert("exceed deadline");
        router.setApprovalForAllWithSig(address(weth1Pair), approved, deadline, sig);
    }

    function testCannotWithdrawWithoutApproval() public {
        Pair pair = normalPair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        router.deposit(token1, token0, 1, alice, depositAmount, 0, period);
        skip(period);

        vm.expectRevert("not operator");
        router.withdraw(address(pair), index, alice);
    }

    function testCannotWithdrawETHWithoutApproval() public {
        Pair pair = weth0Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        vm.startPrank(alice);
        router.depositETH{value: depositAmount}(token1, 1, alice, 0, period);
        router.deposit(token1, WETH, 1, alice, depositAmount, 0, period);
        skip(period);

        vm.expectRevert("not operator");
        (uint token0Amt, uint token1Amt) = router.withdrawETH(address(pair), index, alice);

        index = index + 1;
        vm.expectRevert("not operator");
        (token0Amt, token1Amt) = router.withdrawETH(address(pair), index, alice);
    }

    function testMulticall() public {
        Pair _normalPair = normalPair;
        Pair _weth0Pair = weth0Pair;
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint index = 0;

        // 1. deposit 
        vm.startPrank(alice);
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(Router.deposit.selector, token1, WETH, 1, alice, depositAmount, 0, period);
        data[1] = abi.encodeWithSelector(Router.deposit.selector, token1, token0, 1, alice, depositAmount, 0, period);
        data[2] = abi.encodeWithSelector(Router.deposit.selector, token0, token1, 1, alice, depositAmount, 0, period);
        router.multicall(data); 
        
        skip(period);

        uint deadline = block.timestamp + 1;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken1Balance = IERC20(token1).balanceOf(alice);
        uint oldETHBalance = alice.balance;
        bytes memory sig = _getApprovalSig(address(_normalPair), _nameToKey("alice"), true, deadline);
        bytes memory sig2 = _getApprovalSig(address(_weth0Pair), _nameToKey("alice"), true, deadline);

        // 2. set approval and withdraw
        data = new bytes[](5);
        data[0] = abi.encodeWithSelector(Router.setApprovalForAllWithSig.selector, address(_normalPair), true, deadline, sig);
        data[1] = abi.encodeWithSelector(Router.setApprovalForAllWithSig.selector, address(_weth0Pair), true, deadline, sig2);
        data[2] = abi.encodeWithSelector(Router.withdraw.selector, address(_normalPair), index, alice);
        data[3] = abi.encodeWithSelector(Router.withdraw.selector, address(_normalPair), index + 1, alice);
        data[4] = abi.encodeWithSelector(Router.withdrawETH.selector, address(_weth0Pair), index, alice);
        bytes[] memory results = router.multicall(data); 
        
        uint withdrawToken0Amt;
        uint withdrawToken1Amt;
        uint withdrawETHAmt;
        for(uint i = 2; i < 5; ++i) {
            (uint _token0, uint _token1) = abi.decode(results[i], (uint256, uint256));
            if(i == 4) withdrawETHAmt += _token0;
            else withdrawToken0Amt += _token0;
            withdrawToken1Amt += _token1;
        }

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken1Balance = IERC20(token1).balanceOf(alice);
        uint newETHBalance = alice.balance;
        assertEq(newToken0Balance, oldToken0Balance + withdrawToken0Amt);
        assertEq(newToken1Balance, oldToken1Balance + withdrawToken1Amt);
        assertEq(newETHBalance, oldETHBalance + withdrawETHAmt);
        vm.stopPrank();        
    }

    function testSelfPermit() public {
        vm.startPrank(alice);
        IERC20(token0).approve(address(router), 0);

        uint deadline = block.timestamp + 1;
        uint permitAmount = 10**18;
        (uint8 v, bytes32 r, bytes32 s) = _getSelfPermitSig(token0, _nameToKey("alice"), permitAmount, deadline);
        router.selfPermit(token0, permitAmount, deadline, v, r, s);

        Pair pair = normalPair;
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint depositAmount = 10**18;
        uint period = 1 days;
        uint premium = pair.getPremium(period);

        uint output1 = router.deposit(token0, token1, 1, alice, depositAmount, 0, period);
        (uint token0Amt, uint token1Amt, uint due) = pair.notes(alice, 0);
        assertEq(token0Amt, depositAmount * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(token1Amt, output1 * (premium + PREMIUM_BASE_UNIT) / PREMIUM_BASE_UNIT);
        assertEq(due, block.timestamp + period);

        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - depositAmount);
    }

    function testDepositToGauge() public {
        uint genesis = gauge.genesis();
        deal(sGov, alice, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(sGov).approve(address(router), INITIAL_WEALTH);

        // Week Balance
        //  0      1
        //  1      4
        //  3      9
        router.depositToGauge(address(gauge), 1, alice);
        skip(1 weeks);
        router.depositToGauge(address(gauge), 3, alice);
        skip(2 weeks);
        router.depositToGauge(address(gauge), 5, alice);
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

    function testCannotDepositZeroToGauge() public {
        deal(sGov, alice, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(sGov).approve(address(router), INITIAL_WEALTH);

        vm.expectRevert("invalid amount");
        router.depositToGauge(address(gauge), 0, alice);
        vm.stopPrank();
    }

    function testCannotDepositToGaugeWithInvalidGauge() public {
        deal(sGov, alice, INITIAL_WEALTH);
        vm.startPrank(alice);
        IERC20(sGov).approve(address(router), INITIAL_WEALTH);

        vm.expectRevert("invalid gauge");
        router.depositToGauge(address(0), 1, alice);
        vm.stopPrank();
    }

    function testCannotDepositToGaugeWithoutApproval() public {
        deal(sGov, alice, INITIAL_WEALTH);
        vm.startPrank(alice);

        vm.expectRevert("transferHelper: transferFrom failed");
        router.depositToGauge(address(gauge), 1, alice);
        vm.stopPrank();
    }

    function testStakeDyson() public {
        uint STAKING_RATE_BASE_UNIT = 1e18;
        StakingRateModel currentModel = new StakingRateModel(STAKING_RATE_BASE_UNIT / 16); // initialRate = 1
        IsDYSON(sGov).setStakingRateModel(address(currentModel));
        deal(address(gov), alice, INITIAL_WEALTH);

        vm.startPrank(alice);
        IERC20(gov).approve(address(router), INITIAL_WEALTH);

        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDYSONAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        router.stakeDyson(alice, amount, lockDuration);
        vm.stopPrank();
        
        assertEq(IsDYSON(sGov).balanceOf(alice), sDYSONAmount);
        assertEq(IsDYSON(sGov).dysonAmountStaked(alice), amount);
        assertEq(IsDYSON(sGov).votingPower(alice), sDYSONAmount);
    }

    function testCannotStakeDysonWithInvalidAmount() public {
        uint STAKING_RATE_BASE_UNIT = 1e18;
        StakingRateModel currentModel = new StakingRateModel(STAKING_RATE_BASE_UNIT / 16); // initialRate = 1
        IsDYSON(sGov).setStakingRateModel(address(currentModel));
        deal(address(gov), alice, INITIAL_WEALTH);

        vm.startPrank(alice);
        IERC20(gov).approve(address(router), INITIAL_WEALTH);
        vm.expectRevert("invalid amount");
        router.stakeDyson(alice, 0, 30 days);
        vm.stopPrank();
    }

    function testCannotStakeDysonWithoutApproval() public {
        uint STAKING_RATE_BASE_UNIT = 1e18;
        StakingRateModel currentModel = new StakingRateModel(STAKING_RATE_BASE_UNIT / 16); // initialRate = 1
        IsDYSON(sGov).setStakingRateModel(address(currentModel));
        deal(address(gov), alice, INITIAL_WEALTH);

        vm.prank(alice);
        vm.expectRevert("transferHelper: transferFrom failed");
        router.stakeDyson(alice, 100, 30 days);
    }
 
    function testSwapWithMultiHops() public {
        /** 
        tokens = [token0, token1, token2, token3]
        index = [1, 1, 1]
        Which means user input token0, and get token3 back
        normalPair = (token0, token1)
        normalPair3 = (token1, token2)
        normalPair2 = (token2, token3)
        Path = normalPair(token0 -> token1) -> normalPair3(token1 -> token2) -> normalPair2(token2 -> token3)
        **/
        uint oldToken0Balance = IERC20(token0).balanceOf(alice);
        uint oldToken3Balance = IERC20(token3).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output3; 
        address[] memory tokens = new address[](4);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        output3 = router.swapWithMultiHops(tokens, indexes, alice, swapAmount, 0);
        uint newToken0Balance = IERC20(token0).balanceOf(alice);
        uint newToken3Balance = IERC20(token3).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken3Balance, oldToken3Balance + output3);
    }

    function testSwapETHInWithMultiHops() public {
        /** 
        tokens = [WETH, token1, token2, token3]
        index = [1, 1, 1]
        Which means user input ETH, and get token3 back
        weth0Pair = (WETH, token1)
        normalPair3 = (token1, token2)
        normalPair2 = (token2, token3)
        Path = weth0Pair(WETH -> token1) -> normalPair3(token1 -> token2) -> normalPair2(token2 -> token3)
        **/
        uint oldToken0Balance = alice.balance;
        uint oldToken3Balance = IERC20(token3).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output3; 
        address[] memory tokens = new address[](4);
        tokens[0] = WETH;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        output3 = router.swapETHInWithMultiHops{value: swapAmount}(tokens, indexes, alice, 0);
        uint newToken0Balance = alice.balance;
        uint newToken3Balance = IERC20(token3).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance - swapAmount);
        assertEq(newToken3Balance, oldToken3Balance + output3);
    }

    function testSwapETHOutWithMultiHops() public {
        /** 
        tokens = [token3, token2, token1, WETH]
        index = [1, 1, 1]
        Which means user input token3, and get ETH back
        normalPair2 = (token2, token3)
        normalPair3 = (token1, token2)
        weth0Pair = (WETH, token1)
        Path = normalPair2(token3 -> token2) -> normalPair3(token2 -> token1) -> weth0Pair(token1 -> WETH) 
        **/
        uint oldToken0Balance = alice.balance;
        uint oldToken3Balance = IERC20(token3).balanceOf(alice);
        uint swapAmount = 10**18;
        uint output0; 
        address[] memory tokens = new address[](4);
        tokens[0] = token3;
        tokens[1] = token2;
        tokens[2] = token1;
        tokens[3] = WETH;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        output0 = router.swapETHOutWithMultiHops(tokens, indexes, alice, swapAmount, 0);
        uint newToken0Balance = alice.balance;
        uint newToken3Balance = IERC20(token3).balanceOf(alice);
        assertEq(newToken0Balance, oldToken0Balance + output0);
        assertEq(newToken3Balance, oldToken3Balance - swapAmount);
    }

    function testCannotSwapWithMultiHopsWithInsufficientOutput() public {
        uint swapAmount = 10**18;
        uint minOutput = 10**18;
        address[] memory tokens = new address[](4);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        vm.expectRevert("slippage");
        router.swapWithMultiHops(tokens, indexes, alice, swapAmount, minOutput);
    }

    function testCannotSwapWithMultiHopsWithWrongInput() public {
        uint swapAmount = 10**18;
        address[] memory tokens = new address[](1);
        tokens[0] = token0;

        uint[] memory indexes = new uint[](1);
        indexes[0] = 1;

        vm.startPrank(alice);
        vm.expectRevert("invalid input array length");
        router.swapWithMultiHops(tokens, indexes, alice, swapAmount, 0);
    }

    function testCannotSwapETHInWithMultiHopsWithInsufficientOutput() public {
        uint swapAmount = 10**18;
        uint minOutput = 10**18;
        address[] memory tokens = new address[](4);
        tokens[0] = WETH;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        vm.expectRevert("slippage");
        router.swapETHInWithMultiHops{value: swapAmount}(tokens, indexes, alice, minOutput);
    }

    function testCannotSwapETHOutWithMultiHopsWithInsufficientOutput() public {
        uint swapAmount = 10**18;
        uint minOutput = 10**18;
        address[] memory tokens = new address[](4);
        tokens[0] = token3;
        tokens[1] = token2;
        tokens[2] = token1;
        tokens[3] = WETH;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        vm.expectRevert("slippage");
        router.swapETHOutWithMultiHops(tokens, indexes, alice, swapAmount, minOutput);
    }

    function testCannotSwapETHInWithMultiHopsWithWrongInput() public {
        uint swapAmount = 10**18;
        address[] memory tokens = new address[](4);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        vm.expectRevert("first token must be WETH");
        router.swapETHInWithMultiHops{value: swapAmount}(tokens, indexes, alice, 0);
    }

    function testCannotSwapETHOutWithMultiHopsWithWrongInput() public {
        uint swapAmount = 10**18;
        address[] memory tokens = new address[](4);
        tokens[0] = token0;
        tokens[1] = token1;
        tokens[2] = token2;
        tokens[3] = token3;

        uint[] memory indexes = new uint[](3);
        indexes[0] = 1;
        indexes[1] = 1;
        indexes[2] = 1;

        vm.startPrank(alice);
        vm.expectRevert("last token must be WETH");
        router.swapETHOutWithMultiHops(tokens, indexes, alice, swapAmount, 0);
    }

    function _getApprovalSig(address pair, uint fromKey, bool approved, uint deadline) private view returns (bytes memory) {
        address fromAddr = vm.addr(fromKey);
        bytes32 structHash = keccak256(abi.encode(APPROVE_TYPEHASH, fromAddr, address(router), approved, Pair(pair).nonces(fromAddr), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getPairDomainSeparator(pair), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fromKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getSelfPermitSig(address token, uint fromKey, uint amount, uint deadline) private view returns (uint8 v, bytes32 r, bytes32 s) {
        address fromAddr = vm.addr(fromKey);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, fromAddr, address(router), amount, DYSON(token).nonces(fromAddr), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _getDysonDomainSeparator(token), structHash));
        (v, r, s) = vm.sign(fromKey, digest);
    }

    function _getDysonDomainSeparator(address token) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Dyson Sphere")),
                keccak256(bytes("1")),
                block.chainid,
                token
            )
        );
    }

    function _getPairDomainSeparator(address pair) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("Pair")),
                keccak256(bytes('1')),
                block.chainid,
                pair
            )
        );
    }
}