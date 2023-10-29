pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "../lib/SqrtMath.sol";
import "interface/IERC20.sol";

abstract contract ICO {
    using SqrtMath for *;

    address public owner;
    address public icoToken;
    address public token0;
    address public token1;
    uint public reserve0;
    uint public reserve1;
    uint public totalSupply; // total supply of ICO tokens
    uint public immutable startTime;
    uint public immutable endTime;
    uint public immutable duration;
    // since xy=k, 1 unit is equal to 1 sqrt(k), stand for the share of user
    uint public immutable startingMaxUnits;  
    uint public immutable endingMaxUnits;
    mapping (address => uint) public shareOf;

    event TransferOwnership(address newOwner);
    event Deposit(address from, uint token0Amt, uint token1Amt, uint share);
    event Claim(address to, uint icoTokenAmt);
    
    constructor(address _owner, address _token0, address _token1, uint _totalSupply, uint _startTime, uint _duration, address _icoToken, uint _startingMaxUnits, uint _endingMaxUnits) {
        require(_owner != address(0), "ICO: owner is zero address");
        require(_token0 != address(0), "ICO: token0 is zero address");
        require(_token1 != address(0), "ICO: token1 is zero address");
        require(_startTime >= block.timestamp, "ICO: startTime is early than current time");
        require(_duration > 0, "ICO: duration is zero");
        require(_endingMaxUnits < _startingMaxUnits, "ICO: endingMaxUnits is greater than startingMaxUnits");

        owner = _owner;
        token0 = _token0;
        token1 = _token1;
        totalSupply = _totalSupply;
        startTime = _startTime;
        duration = _duration;
        endTime = _startTime + _duration;
        icoToken = _icoToken;
        startingMaxUnits = _startingMaxUnits;
        endingMaxUnits = _endingMaxUnits;
    }

    /**
     * @dev user can deposit token0 and token1 to get icoToken
     * @param token0Amt amount of token0 to deposit
     * @param token1Amt amount of token1 to deposit
     * @param minUnits minimum units of icoToken to get
     * ---- Additional logic Waiting for implementation: lockPeriod
     */
    function deposit(uint token0Amt, uint token1Amt, uint minUnits) external virtual;

    /**
     * @dev user can claim their icoToken after the ICO ended
     */
    function claim() external virtual;

    /**
     * @dev owner can claim the remaining tokens after the ICO ended
     */
    function ownerClaim(address to) external virtual;
        
    function _deposit(uint token0Amt, uint token1Amt, uint minUnits) internal returns (uint){
        require(block.timestamp >= startTime, "ICO: NOT_STARTED_YET");
        require(block.timestamp <= endTime, "ICO: ALREADY_ENDED");
        require(token0Amt > 0 || token1Amt > 0, "ICO: AMOUNTS_OF_BOTH_TOKENS_ARE_ZERO");

        uint currentMaxUnits = getCurrentMaxUnits();
        uint _reserve0 = reserve0;
        uint _reserve1 = reserve1;
        uint currentUnits = getCurrentUnits(_reserve0, _reserve1);
        uint share = calculateNewShare(_reserve0, _reserve1, token0Amt, token1Amt);
        require(currentUnits + share <= currentMaxUnits, "ICO: TOTAL_UNITS_EXCEED_MAXUNITS");
        require(share >= minUnits, "ICO: SHARE_LESS_THAN_MINUNITS");

        IERC20(token0).transferFrom(msg.sender, address(this), token0Amt);
        IERC20(token1).transferFrom(msg.sender, address(this), token1Amt);
        reserve0 += token0Amt;
        reserve1 += token1Amt;
        return share;
    }

    function getCurrentUnits(uint _reserve0, uint _reserve1) public pure returns(uint) {
        return (_reserve1 * _reserve0).sqrt();
    }

    /**
     * @notice simulate deposit and calculate the share of icoToken after deposit
     * @param _reserve0 current reserve0
     * @param _reserve1 current reserve1
     * @param token0Amt amount of token0 to deposit
     * @param token1Amt amount of token1 to deposit
     */
    function calculateNewShare(uint _reserve0, uint _reserve1, uint token0Amt, uint token1Amt) public pure returns (uint share) {
        uint r0 = _reserve0 + token0Amt;
        uint r1 = _reserve1 + token1Amt;
        require(r0 > 0 && r1 > 0, "ICO: INSUFFICIENT_LIQUIDITY");
        uint newCurrentUnits = (r0 * r1).sqrt();
        uint currentUnits = getCurrentUnits(_reserve0, _reserve1);
        share = newCurrentUnits - currentUnits;
    }

    /**
     * @notice get the current units of icoToken
     * @dev the max units of icoToken would decline linearly over time
     */
    function getCurrentMaxUnits() public view returns (uint currentMaxUnits) {
        uint timeElasped = block.timestamp - startTime;
        // using linear interpolation to calculate currentMaxUnits
        currentMaxUnits = startingMaxUnits - (timeElasped * (startingMaxUnits - endingMaxUnits) / duration );
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "OWNER_CANNOT_BE_ZERO");
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

}

contract ICOStrategy is ICO {

    constructor(address _owner, address _token0, address _token1, uint _totalSupply, uint _startTime, uint _duration, address _icoToken, uint _startingMaxUnits, uint _endingMaxUnits) 
    ICO(_owner, _token0, _token1, _totalSupply, _startTime, _duration, _icoToken, _startingMaxUnits, _endingMaxUnits) {}

    function deposit(uint token0Amt, uint token1Amt, uint minUnits) external override {
        uint share = _deposit(token0Amt, token1Amt, minUnits);
        shareOf[msg.sender] += share;
        emit Deposit(msg.sender, token0Amt, token1Amt, share);
    }

    function claim() external override {
        require(block.timestamp > endTime, "ICO: NOT_ENDED_YET");
        require(shareOf[msg.sender] > 0, "ICO: NO_SHARE");
        uint soldoutUnits = getCurrentUnits(reserve0, reserve1);
        uint share = shareOf[msg.sender];
        uint icoTokenAmt = totalSupply * share / soldoutUnits;
        shareOf[msg.sender] = 0;
        IERC20(icoToken).transfer(msg.sender, icoTokenAmt);
        emit Claim(msg.sender, icoTokenAmt);
    }

    function ownerClaim(address to) external override onlyOwner {
        require(to != address(0), "ICO: receiver is zero address");
        require(block.timestamp > endTime, "ICO: NOT_ENDED_YET");
        uint token0Balance = IERC20(token0).balanceOf(address(this));
        uint token1Balance = IERC20(token1).balanceOf(address(this));
        IERC20(token0).transfer(to, token0Balance);
        IERC20(token1).transfer(to, token1Balance);
    }
}