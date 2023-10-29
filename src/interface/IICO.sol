pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IICO {
    event TransferOwnership(address newOwner);
    event Deposit(address from, uint token0Amt, uint token1Amt, uint share);
    event Claim(address to, uint icoTokenAmt);

    function owner() external view returns (address);
    function icoToken() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function reserve0() external view returns (uint);
    function reserve1() external view returns (uint);
    function totalSupply() external view returns (uint);
    function startTime() external view returns (uint);
    function endTime() external view returns (uint);
    function duration() external view returns (uint);
    function startingMaxUnits() external view returns (uint);
    function endingMaxUnits() external view returns (uint);
    function shareOf(address user) external view returns (uint);
    function deposit(uint token0Amt, uint token1Amt, uint minUnits) external;
    function claim() external;
    function ownerClaim(address to) external;
    function getCurrentUnits(uint _reserve0, uint _reserve1) external pure returns(uint);
    function calculateNewShare(uint _reserve0, uint _reserve1, uint token0Amt, uint token1Amt) external pure returns (uint share);
    function getCurrentMaxUnits() external view returns (uint currentMaxUnits);
    function transferOwnership(address _owner) external;
}