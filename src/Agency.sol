pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./AgentNFT.sol";
import "./lib/TransferHelper.sol";

/// @title Referral system contract
/// @notice If a user deposits in Pair and has registered in referral system,
/// he will get extra DYSON token as reward.
/// Each user in the referral system is an `Agent`.
/// Referral of a agent is called the `child` of the agent.
contract Agency {
    using TransferHelper for address;

    bytes32 public constant REGISTER_ONCE_TYPEHASH = keccak256("register(address child)"); // onceSig
    bytes32 public constant REGISTER_PARENT_TYPEHASH = keccak256("register(address once,uint256 deadline,uint256 price)"); // parentSig
    /// @notice Max number of children, i.e., referrals, per agent
    /// Note that this limit is not forced on root agent
    uint constant MAX_NUM_CHILDREN = 3;
    /// @notice Amount of time a new agent have to wait before he can refer a new user
    uint constant REGISTER_DELAY = 4 hours;
    /// @notice Cooldown time before an agent can transfer his agent
    uint constant TRANSFER_CD = 60000;
    
    AgentNFT public immutable agentNFT;

    /// @dev For EIP-2612 permit
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @member owner Owner of the agent data
    /// @member gen Agent's generation in the referral system
    /// @member birth Timestamp when the agent registerred in the referral system
    /// @member parentId Id of the agent's parent, i.e., it's referrer
    /// @member childrenId Ids of the agent's children, i.e., referrals

    struct Agent {
        address owner;
        uint gen;
        uint birth;
        uint parentId;
        uint[] childrenId;
    }

    address public owner;
    /// @notice Number of users in the referral system
    uint public totalSupply;

    /// @notice User's id in the referral system
    /// Param is User's address
    mapping(address => uint) public whois;
    /// @notice User's agent
    /// Param is User's id in the referral system
    mapping(uint => Agent) internal agents;
    /// @notice Record the time when a user can transfer his agent
    mapping(uint => uint) public transferCooldown;
    /// @notice Record if an invite code has been used
    mapping(address => bool) public oneTimeCodes;
    /// @notice Record if a hash has been presigned by an address
    mapping(address => mapping(bytes32 => bool)) public presign;
    /// @notice Record if an address is a controller
    mapping (address => bool) public isController;

    event TransferOwnership(address newOwner);
    event Register(uint indexed referrer, uint referee);
    event Sign(address indexed signer, bytes32 digest);

    constructor(address _owner, address root) {
        require(_owner != address(0), "invalid owner");
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Agency")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));

        owner = _owner;

        AgentNFT _agentNFT = new AgentNFT(address(this));
        agentNFT = _agentNFT;
        // Initialize root
        uint id = ++totalSupply; // root agent has id 1
        whois[root] = id;
        Agent storage rootAgent = agents[id];
        rootAgent.owner = root;
        rootAgent.birth = block.timestamp;
        rootAgent.parentId = id; // root agent's parent is also root agent itself
        _agentNFT.onMint(root, id);
        emit Register(id, id);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) onlyOwner external {
        tokenAddress.safeTransfer(to, amount);
    }

    function addController(address _controller) external onlyOwner {
        isController[_controller] = true;
    }

    function removeController(address _controller) external onlyOwner {
        isController[_controller] = false;
    }

    /// @notice Add new child agent to root agent. This child will have the privilege of being a 1st generation agent.
    /// This function can only be executed by admin, which is either `owner` or `controller`.
    /// @param newUser User of the new agent
    /// @return id Id of the new agent
    function adminAdd(address newUser) external returns (uint id) {
        require(msg.sender == owner || isController[msg.sender], "forbidden");
        require(whois[newUser] == 0, "occupied");
        id = _newAgent(newUser, 1);
    }

    /// @notice Transfer agent data to another user
    /// Can not transfer to a user who already has an agent.
    /// @param from previous owner of the agent
    /// @param to User who will receive the agent
    /// @param id index of the agent to be transfered
    /// @return True if transfer succeed
    function transfer(address from, address to, uint id) external returns (bool) {
        require(msg.sender == address(agentNFT), "forbidden");
        require(to != address(0), "transfer invalid address");
        require(id != 0, "nothing to transfer");
        require(id == whois[from], "forbidden");
        require(transferCooldown[id] < block.timestamp, "cd");
        Agent storage agent = agents[id];
        require(whois[to] == 0, "occupied");
        agent.owner = to;
        whois[to] = id;
        whois[from] = 0;
        // agent can not be transfered again until cooldown time, (gen + 1) * TRANSFER_CD, 
        // which is 10 times as long as the cooldown time of swapping SP to DYSON
        transferCooldown[id] = block.timestamp + (agent.gen + 1) * TRANSFER_CD; 
        return true;
    }

    /// @dev Create new `Agent` data and update the link between the agent and it's parent agent
    function _newAgent(address _owner, uint parentId) internal returns (uint id) {
        require(_owner != address(0), "new agent invalid address");
        id = ++totalSupply;
        whois[_owner] = id;
        Agent storage parent = agents[parentId];
        Agent storage child = agents[id];
        parent.childrenId.push(id);
        child.owner = _owner;
        child.gen = parent.gen + 1;
        child.birth = block.timestamp;
        child.parentId = parentId;
        agentNFT.onMint(_owner, id);
        emit Register(parentId, id);
    }

    function _getHashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    /// @notice User register in the referral system by providing an one time invite code: `onceSig`
    /// and his referrer's signature: `parentSig`.
    /// User can not register if he already has an agent.
    /// User can not register if the referrer already has maximum number of child agents.
    /// User can not register if the referrer is new and has not passed the register delay
    /// @notice If the referral code is presigned, use parent's address for parentSig
    /// @param parentSig Referrer's signature or referrer's address
    /// @param onceSig Invite code
    /// @param deadline Deadline of the invite code, set by the referrer
    /// @return id Id of the new agent
    function register(bytes memory parentSig, bytes memory onceSig, uint deadline) payable external returns (uint id) {
        require(block.timestamp < deadline, "exceed deadline");
        require(whois[msg.sender] == 0, "already registered");

        bytes32 onceSigDigest = _getHashTypedData(keccak256(abi.encode(
            REGISTER_ONCE_TYPEHASH,
            msg.sender
        )));
        address once = _ecrecover(onceSigDigest, onceSig);
        require(once != address(0), "invalid once sig");
        require(oneTimeCodes[once] == false, "signature is used");

        bytes32 parentSigDigest = _getHashTypedData(keccak256(abi.encode(
            REGISTER_PARENT_TYPEHASH,
            once,
            deadline,
            msg.value
        )));
        address _parent;
        if(parentSig.length == 65) {
            _parent = _ecrecover(parentSigDigest, parentSig);
        }
        else if(parentSig.length == 20) {
            assembly {
                _parent := mload(add(parentSig, 20))
            }
            require(presign[_parent][parentSigDigest], "invalid parent sig");
        }
        require(_parent != address(0), "invalid parent sig");

        uint parentId = whois[_parent];
        require(parentId != 0, "invalid parent");
        Agent storage parent = agents[parentId];
        require(parent.childrenId.length < MAX_NUM_CHILDREN, "no empty slot");
        require(parent.birth + REGISTER_DELAY <= block.timestamp, "not ready");

        id = _newAgent(msg.sender, parentId);
        oneTimeCodes[once] = true;
        if(msg.value > 0) {
            _parent.safeTransferETH(msg.value);
        }
    }

    /// @dev parent do onchain presign for a referral code
    function sign(bytes32 digest) external {
        presign[msg.sender][digest] = true;
        emit Sign(msg.sender, digest);
    }

    function getHashTypedData(bytes32 structHash) external view returns (bytes32) {
        return _getHashTypedData(structHash);
    }

    /// @notice User's agent data
    /// @param _owner User's address
    /// @return ref Parent agent's owner address
    /// @return gen Generation of user's agent
    function userInfo(address _owner) external view returns (address ref, uint gen) {
        Agent storage agent = agents[whois[_owner]];
        ref = agents[agent.parentId].owner;
        gen = agent.gen;
    }

    /// @notice Get agent data by user's id
    /// @param id Id of the user
    /// @return User's agent data
    function getAgent(uint id) external view returns (address, uint, uint, uint, uint[] memory) {
        Agent storage agent = agents[id];
        return(agent.owner, agent.gen, agent.birth, agent.parentId, agent.childrenId);
    }

    function _ecrecover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }

            if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
                return address(0);
            } else if (v != 27 && v != 28) {
                return address(0);
            } else {
                return ecrecover(hash, v, r, s);
            }
        } else {
            return address(0);
        }
    }

}
