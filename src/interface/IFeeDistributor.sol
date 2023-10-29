pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IFeeDistributor {

    event FeeDistributed(uint token0ToDAO, uint token1ToDAO, uint token0ToBribe, uint token1ToBribe);

    function owner() external view returns (address);
    function pair() external view returns (address);
    function bribe() external view returns (address);
    function pairToken0() external view returns (address);
    function pairToken1() external view returns (address);
    function daoWallet() external view returns (address);
    function feeRateToDao() external view returns (uint);
    function setFeeRateToDao(uint _feeRateToDAO) external;
    function setDaoWallet(address _daoWallet) external;
    function setBribe(address _bribe) external;
    function setPair(address _pair) external;
    function distributeFee() external;
}