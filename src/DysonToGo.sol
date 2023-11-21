pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0

import "interface/IPair.sol";
import "interface/IWETH.sol";
import "interface/IFactory.sol";
import "interface/IFarm.sol";
import "interface/IGauge.sol";
import "interface/IBribe.sol";
import "interface/IAgentNFT.sol";
import "interface/IAgency.sol";
import "interface/IERC721Receiver.sol";
import "./lib/TransferHelper.sol";
import "./util/AddressBook.sol";

contract DysonToGo is IERC721Receiver {
    using TransferHelper for address;

    uint private constant MAX_ADMIN_FEE_RATIO = 1e18;
    address public immutable ADDRESS_BOOK;
    address public immutable WETH;
    address public immutable DYSON;
    address public immutable sDYSON;
    address public immutable FACTORY;
    address public immutable FARM;
    address public immutable AgentNFT;
    address public immutable Agency;
    bytes32 public immutable CODE_HASH;

    struct Position {
        uint index;
        uint spAmount;
        bool hasDepositedAsset;
    }

    address public owner;
    uint public adminFeeRatio;
    uint public spPool;
    uint public dysonPool;
    uint public spSnapshot; //sp in farm at last update
    uint public spPending; //sp to be added to pool
    uint public lastUpdateTime;
    uint public updatePeriod = 5 hours; //depends on agent tier
    uint private unlocked = 1;

    mapping(address => mapping(address => uint)) public positionsCount;
    mapping(address => mapping(address => mapping(uint => Position))) public positions;

    event TransferOwnership(address newOwner);
    event Deposit(address indexed pair, address indexed user, uint index, uint spAmount);
    event Withdraw(address indexed pair, address indexed user, uint index, uint dysonAmount);
    event DYSONReceived(uint ownerAmount, uint poolAmount);

    constructor(address _owner, address _WETH, address _addressBook) {
        require(_owner != address(0), "owner cannot be zero");
        require(_WETH != address(0), "invalid weth");
        AddressBook addressBook = AddressBook(_addressBook);
        owner = _owner;
        ADDRESS_BOOK = _addressBook;
        WETH = _WETH;
        DYSON = addressBook.govToken();
        sDYSON = addressBook.govTokenStaking();
        FACTORY = addressBook.factory();
        FARM = addressBook.farm();
        AgentNFT = addressBook.agentNFT();
        Agency = addressBook.agency();
        CODE_HASH = IFactory(FACTORY).getInitCodeHash();
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    modifier lock() {
        require(unlocked == 1, 'locked');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'identical addresses');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'zero address');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, bytes32 initCodeHash, address tokenA, address tokenB, uint id) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1, id)), //salt
                initCodeHash
            )))));
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;
        emit TransferOwnership(_owner);
    }

    /// @notice Allow another address to transfer token from this contract
    /// @param tokenAddress Address of token to approve
    /// @param contractAddress Address to grant allowance
    /// @param enable True to enable allowance. False otherwise.
    function rely(address tokenAddress, address contractAddress, bool enable) external onlyOwner {
        require(tokenAddress != DYSON, "invalid token"); // cannot approve DYSON to arbitrary address
        tokenAddress.safeApprove(contractAddress, enable ? type(uint).max : 0);
    }

    function relyDysonPair(address token, uint index, bool enable) external onlyOwner {
        address pair = pairFor(FACTORY, CODE_HASH, DYSON, token, index);
        DYSON.safeApprove(pair, enable ? type(uint).max : 0);
    }

    function setAdminFeeRatio(uint ratio) external onlyOwner {
        require(ratio <= MAX_ADMIN_FEE_RATIO, "invalid admin fee ratio");
        adminFeeRatio = ratio;
    }

    function setUpdatePeriod(uint period) external onlyOwner {
        updatePeriod = period;
    }

    function gaugeDeposit(address gauge, uint amount) external onlyOwner {
        require(gauge != address(0), "invalid gauge");
        IGauge(gauge).deposit(amount, address(this));
    }

    function gaugeApplyWithdrawal(address gauge, uint amount) external onlyOwner {
        require(gauge != address(0), "invalid gauge");
        IGauge(gauge).applyWithdrawal(amount);
    }

    function gaugeWithdraw(address gauge) external onlyOwner {
        require(gauge != address(0), "invalid gauge");
        IGauge(gauge).withdraw();
    }

    function bribeClaimRewards(address gauge, address token, uint[] calldata week) external onlyOwner returns (uint amount) {
        address bribe = AddressBook(ADDRESS_BOOK).bribeOfGauge(gauge);
        if (week.length == 1)
            amount = IBribe(bribe).claimReward(token, week[0]);
        else
            amount = IBribe(bribe).claimRewards(token, week);
        token.safeTransfer(owner, amount);
    }

    function bribeClaimRewardsMultipleTokens(address gauge, address[] calldata token, uint[][] calldata week) external onlyOwner returns (uint[] memory amounts) {
        address bribe = AddressBook(ADDRESS_BOOK).bribeOfGauge(gauge);
        amounts = IBribe(bribe).claimRewardsMultipleTokens(token, week);  
        for(uint i = 0; i < amounts.length; ++i) {
            token[i].safeTransfer(owner, amounts[i]);
        }
    }

    function adminWithdrawSdyson(uint amount) external onlyOwner {
        sDYSON.safeTransfer(owner, amount);
    }

    function adminWithdrawAgent(uint tokenId) external onlyOwner {
        IAgentNFT(AgentNFT).safeTransferFrom(address(this), owner, tokenId);
    }

    /// @notice This contract can only receive ETH coming from WETH contract,
    /// i.e., when it withdraws from WETH
    receive() external payable {
        require(msg.sender == WETH);
    }

    function update() external lock returns (uint sp) {
        sp = _update();
        spSnapshot = sp;
    }

    function _update() internal returns (uint spInFarm) {
        if(lastUpdateTime + updatePeriod < block.timestamp) {
            try IFarm(FARM).swap(address(this)) {} catch {}
            lastUpdateTime = block.timestamp;
        }
        spInFarm = IFarm(FARM).balanceOf(address(this));
        if(spInFarm < spSnapshot) {
            spPool += spPending;
            spPending = 0;
            uint newBalance = IERC20(DYSON).balanceOf(address(this));
            if (newBalance > dysonPool) {
                uint dysonAdded = newBalance - dysonPool;
                uint adminFee = dysonAdded * adminFeeRatio / MAX_ADMIN_FEE_RATIO;
                uint poolIncome = dysonAdded - adminFee;
                dysonPool += poolIncome;
                DYSON.safeTransfer(owner, adminFee);
                emit DYSONReceived(adminFee, poolIncome);
            }
        }
    }

    function _deposit(address tokenIn, address tokenOut, uint index, uint input, uint minOutput, uint time) internal returns (uint output) {
        uint spBefore = _update();
        address pair = pairFor(FACTORY, CODE_HASH, tokenIn, tokenOut, index);
        (address token0,) = sortTokens(tokenIn, tokenOut);
        uint noteCount = IPair(pair).noteCount(address(this));
        if(tokenIn == token0)
            output = IPair(pair).deposit0(address(this), input, minOutput, time);
        else
            output = IPair(pair).deposit1(address(this), input, minOutput, time);
        uint spAfter = IFarm(FARM).balanceOf(address(this));
        uint spAdded = spAfter - spBefore;
        spPending += spAdded;
        spSnapshot = spAfter;
        Position storage position = positions[pair][msg.sender][positionsCount[pair][msg.sender]];
        position.index = noteCount;
        position.spAmount = spAdded;
        position.hasDepositedAsset = true;
        positionsCount[pair][msg.sender]++;
        emit Deposit(pair, msg.sender, noteCount, spAdded);
    }

    function deposit(address tokenIn, address tokenOut, uint index, uint input, uint minOutput, uint time) external lock returns (uint output) {
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        return _deposit(tokenIn, tokenOut, index, input, minOutput, time);
    }

    function depositETH(address tokenOut, uint index, uint minOutput, uint time) external payable lock returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        return _deposit(WETH, tokenOut, index, msg.value, minOutput, time);
    }

    function _claimDyson(address to, uint sp) internal returns (uint dysonAmount) {
        if (sp == 0) return 0;
        spSnapshot = _update();
        dysonAmount = dysonPool * sp / (spPool + sp);
        spPool -= sp;
        dysonPool -= dysonAmount;
        DYSON.safeTransfer(to, dysonAmount);
    }

    function withdraw(address pair, uint index, address to) external lock returns (uint token0Amt, uint token1Amt, uint dysonAmt) {
        Position storage position = positions[pair][msg.sender][index];
        require(position.hasDepositedAsset, "not deposited");
        position.hasDepositedAsset = false;
        (token0Amt, token1Amt) = IPair(pair).withdraw(position.index, to);
        dysonAmt = _claimDyson(to, position.spAmount);
        emit Withdraw(pair, msg.sender, index, dysonAmt);
    }

    function withdrawETH(address pair, uint index, address to) external lock returns (uint token0Amt, uint token1Amt, uint dysonAmt) {
        Position storage position = positions[pair][msg.sender][index];
        require(position.hasDepositedAsset, "not deposited");
        position.hasDepositedAsset = false;
        (token0Amt, token1Amt) = IPair(pair).withdraw(position.index, address(this));
        address token = token0Amt > 0 ? IPair(pair).token0() : IPair(pair).token1();
        uint amount = token0Amt > 0 ? token0Amt : token1Amt;
        if (token == WETH) {
            IWETH(WETH).withdraw(amount);
            to.safeTransferETH(amount);
        } else {
            token.safeTransfer(to, amount);
        }
        dysonAmt = _claimDyson(to, position.spAmount);
        emit Withdraw(pair, msg.sender, index, dysonAmt);
    }

    function sign(bytes32 digest) external onlyOwner {
        IAgency(Agency).sign(digest);
    }

    function onERC721Received(address, address, uint, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}

/**
 * @title DysonToGoFactory
 * @notice Factory contract for DysonToGo
 */
contract DysonToGoFactory {
    address public immutable ADDRESS_BOOK;
    address public immutable WETH;

    address public owner;
    address[] public allInstances;
    /// @notice Record if an address is a controller
    mapping (address => bool) public isController;

    event TransferOwnership(address newOwner);
    event DysonToGoCreated(address dysonToGo);

    constructor(address _owner, address _WETH, address _addressBook) {
        require(_owner != address(0), "owner cannot be zero");
        require(_WETH != address(0), "invalid weth");
        require(_addressBook != address(0), "invalid address book");
        owner = _owner;
        ADDRESS_BOOK = _addressBook;
        WETH = _WETH;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    function allInstancesLength() external view returns (uint) {
        return allInstances.length;
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;
        emit TransferOwnership(_owner);
    }

    function createDysonToGo(address user) external returns (address dysonToGo) {
        require(msg.sender == owner || isController[msg.sender], "forbidden");
        require(user != address(0), "user cannot be zero");
        dysonToGo = address(new DysonToGo(user, WETH, ADDRESS_BOOK));
        allInstances.push(dysonToGo);
        emit DysonToGoCreated(dysonToGo);
    }

    function addController(address _controller) external onlyOwner {
        isController[_controller] = true;
    }

    function removeController(address _controller) external onlyOwner {
        isController[_controller] = false;
    }

}
