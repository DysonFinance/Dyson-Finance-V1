pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./Agency.sol";

/// @title Referral system contract for foreign chain
/// @notice work mostly like Agency contract
/// but admin can add agent that's not tier 1
contract ForeignAgency is Agency {

    constructor(address _owner, address root) Agency(_owner, root) {}

    /// @notice Add new child agent to root agent with specified `gen` and `slotUsed`
    /// This function can only be executed by `owner` or `controller`.
    /// @param newUser User of the new agent
    /// @param gen Generation of the new agent
    /// @param slotUsed Number of slot that has already been used 
    /// @return id Id of the new agent
    function adminAddForeign(address newUser, uint gen, uint slotUsed) external returns (uint id) {
        require(msg.sender == owner || isController[msg.sender], "FORBIDDEN");
        require(whois[newUser] == 0, "OCCUPIED");
        require(newUser != address(0), "NEW_AGENT_INVALID_ADDRESS");
        id = ++totalSupply;
        whois[newUser] = id;
        Agent storage parent = agents[1];
        Agent storage child = agents[id];
        parent.childrenId.push(id);
        child.owner = newUser;
        child.gen = gen;
        child.birth = block.timestamp;
        child.parentId = 1;
        for(uint i = 0; i < slotUsed; ++i)
            child.childrenId.push(0); // id 0 as dummy
        agentNFT.onMint(newUser, id);
        emit Register(1, id);
    }

}
