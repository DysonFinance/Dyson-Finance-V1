pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IAgency {
    struct Agent {
        address owner;
        uint gen;
        uint birth;
        uint parentId;
        uint[] childrenId;
    }

    event TransferOwnership(address newOwner);
    event Register(uint indexed referrer, uint referee);
    event Sign(address indexed signer, bytes32 digest);

    function REGISTER_ONCE_TYPEHASH() external view returns (bytes32);
    function REGISTER_PARENT_TYPEHASH() external view returns (bytes32);
    function MAX_NUM_CHILDREN() external view returns (uint);
    function REGISTER_DELAY() external view returns (uint);
    function TRANSFER_CD() external view returns (uint);
    function agentNFT() external view returns (address);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function whois(address agent) external view returns (uint);
    function oneTimeCodes(address once) external view returns (bool);
    function presign(address agent, bytes32 digest) external view returns (bool);
    function isController(address agent) external view returns (bool);
    function owner() external view returns (address);

    function userInfo(address agent) external view returns (address ref, uint gen);
    function transfer(address from, address to, uint id) external returns (bool);
    function totalSupply() external view returns (uint);
    function getAgent(uint id) external view returns (address, uint, uint, uint, uint[] memory);
    function transferOwnership(address owner) external;
    function addController(address _controller) external;
    function removeController(address _controller) external;
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function adminAdd(address newUser) external returns (uint id);
    function register(bytes memory parentSig, bytes memory onceSig, uint deadline) payable external returns (uint id);
    function sign(bytes32 digest) external;
    function getHashTypedData(bytes32 structHash) external view returns (bytes32);
    function transferCooldown(uint id) external view returns (uint);
}