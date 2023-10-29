pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

contract AddressBook {
    address public owner;
    address public govToken;
    address public govTokenStaking;
    address public factory;
    address public router;
    address public farm;
    address public agency;
    address public agentNFT;
    address public treasury;
    address public nextAddressBook; //migrated if not zero address

    mapping(address => mapping(address => uint256)) private _canonicalIdOfPair;
    mapping(address => address) public bribeOfGauge;

    event File(bytes32 indexed name, address value);
    event SetCanonicalIdOfPair(address indexed token0, address indexed token1, uint256 canonicalId);
    event SetBribeOfGauge(address indexed gauge, address indexed bribe);

    constructor(address _owner) {
        owner = _owner;
    }

    function file(bytes32 name, address value) external {
        require(msg.sender == owner, "AddressBook: FORBIDDEN");
        if (name == "owner") owner = value;
        else if (name == "govToken") govToken = value;
        else if (name == "govTokenStaking") govTokenStaking = value;
        else if (name == "factory") factory = value;
        else if (name == "router") router = value;
        else if (name == "farm") farm = value;
        else if (name == "agency") agency = value;
        else if (name == "agentNFT") agentNFT = value;
        else if (name == "treasury") treasury = value;
        else if (name == "nextAddressBook") nextAddressBook = value;
        else revert("AddressBook: NOT_FOUND");
        emit File(name, value);
    }

    function getCanonicalIdOfPair(address token0, address token1) external view returns (uint256) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        return _canonicalIdOfPair[token0][token1];
    }

    function setCanonicalIdOfPair(address token0, address token1, uint256 canonicalId) external {
        require(msg.sender == owner, "AddressBook: FORBIDDEN");
        require(token0 != token1, "AddressBook: IDENTICAL_ADDRESSES");
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        _canonicalIdOfPair[token0][token1] = canonicalId;
        emit SetCanonicalIdOfPair(token0, token1, canonicalId);
    }

    function setBribeOfGauge(address gauge, address bribe) external {
        require(msg.sender == owner, "AddressBook: FORBIDDEN");
        bribeOfGauge[gauge] = bribe;
        emit SetBribeOfGauge(gauge, bribe);
    }
}
