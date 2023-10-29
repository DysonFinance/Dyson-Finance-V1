pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IAddressBook {
    event File(bytes32 indexed name, address value);
    event SetCanonicalIdOfPair(address indexed token0, address indexed token1, uint256 canonicalId);
    event SetBribeOfGauge(address indexed gauge, address indexed bribe);
    
    function owner() external view returns (address);
    function govToken() external view returns (address);
    function govTokenStaking() external view returns (address);
    function factory() external view returns (address);
    function router() external view returns (address);
    function farm() external view returns (address);
    function agency() external view returns (address);
    function agentNFT() external view returns (address);
    function treasury() external view returns (address);
    function nextAddressBook() external view returns (address);
    function bribeOfGauge(address gauge) external view returns (address);
    function file(bytes32 name, address value) external;
    function getCanonicalIdOfPair(address token0, address token1) external view returns (uint256);
    function setCanonicalIdOfPair(address token0, address token1, uint256 canonicalId) external;
    function setBribeOfGauge(address gauge, address bribe) external;
}
