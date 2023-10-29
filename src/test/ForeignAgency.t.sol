// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import 'src/ForeignAgency.sol';

contract ForeignAgencyTest is Test {
    uint public constant rootKey = 1;
    address public root = vm.addr(1);
    address public testOwner = address(this);
    address public controller = vm.addr(100);
    uint[] public adminKeys = [2, 3, 4];
    address[] public tier1s = [vm.addr(2), vm.addr(3), vm.addr(4)];
    uint onceSigKey = 66666;
    ForeignAgency agency = new ForeignAgency(address(this), root);
    AgentNFT agentNFT;

    struct Agent {
        address owner;
        uint gen;
        uint birth;
        uint parentId;
        uint[] childrenId;
    }

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant REGISTER_ONCE_TYPEHASH = keccak256("register(address child)"); // onceSig
    bytes32 public constant REGISTER_PARENT_TYPEHASH = keccak256("register(address once,uint256 deadline,uint256 price)"); // parentSig

    function setUp() public {
        agency.addController(controller);
        for (uint i = 0; i < tier1s.length; i++) {
            agency.adminAdd(tier1s[i]);
        }
        DOMAIN_SEPARATOR = agency.DOMAIN_SEPARATOR();

        agentNFT = agency.agentNFT();

        // Construct an initial agency tree with three generations.
        // Id = NFT Token Id = Private Key
        // Root:               1
        // Tier1:     2,       3,         4
        // Normal: 5, 6, 7, 8, 9, 10, 11, 12, 13
        _registerFullTree(2);
        // Skip so the latest registered account can register new ones 
        skip(4 hours);
    }

    function testAdminAddForeign() public {
        // assume the new agent is registered on the other chain, gen = 10, slotUsed = 2
        uint originGen = 10;
        uint slotUsed = 2;
        uint nextNFTTokenId = agentNFT.totalSupply() + 1;
        address newAgent = address(5566);
        // Add new agent
        agency.adminAddForeign(newAgent, originGen, slotUsed);

        assertEq(agentNFT.balanceOf(newAgent), 1);
        assertEq(agentNFT.ownerOf(nextNFTTokenId), newAgent);
        (address ref, uint gen) = agency.userInfo(newAgent);
        assertEq(ref, root); // new agent's parent is root.
        assertEq(gen, originGen); // new agent's generation stays unchanged.

        uint newAgentId = agency.whois(newAgent);
        (,,,, uint[] memory children) = agency.getAgent(newAgentId);
        assertEq(children.length, slotUsed);
        assertEq(children[0], 0);
        assertEq(children[1], 0);
    }

    function testAdminAddForeignByController() public {
        // assume the new agent is registered on the other chain, gen = 10, slotUsed = 2
        uint originGen = 10;
        uint slotUsed = 2;
        uint nextNFTTokenId = agentNFT.totalSupply() + 1;
        address newAgent = address(5566);
        // Add new agent
        vm.prank(controller);
        agency.adminAddForeign(newAgent, originGen, slotUsed);

        assertEq(agentNFT.balanceOf(newAgent), 1);
        assertEq(agentNFT.ownerOf(nextNFTTokenId), newAgent);
        (address ref, uint gen) = agency.userInfo(newAgent);
        assertEq(ref, root); // new agent's parent is root.
        assertEq(gen, originGen); // new agent's generation is unchanged.

        uint newAgentId = agency.whois(newAgent);
        (,,,, uint[] memory children) = agency.getAgent(newAgentId);
        assertEq(children.length, 2);
        assertEq(children[0], 0);
        assertEq(children[1], 0);
    }

    function testCannotAdminAddByNonController() public {
        // Even tier1 can not use adminAdd().
        uint originGen = 10;
        uint slotUsed = 2;
        address tier1 = tier1s[0];
        address newAgent = vm.addr(4);
        vm.prank(tier1);
        vm.expectRevert("FORBIDDEN");
        agency.adminAddForeign(newAgent, originGen, slotUsed);
    }

    function testCannotAdminAddZeroAddress() public {
        uint originGen = 10;
        uint slotUsed = 2;
        address newUser = address(0);
        vm.expectRevert("NEW_AGENT_INVALID_ADDRESS");
        agency.adminAddForeign(newUser, originGen, slotUsed);
    }

    function testCannotAdminAddAlreadyRegisteredAddress() public {
        uint originGen = 10;
        uint slotUsed = 2;
        address tier1 = tier1s[0];
        vm.expectRevert("OCCUPIED");
        agency.adminAddForeign(tier1, originGen, slotUsed);

        // Check userInfo
        (address ref, uint gen) = agency.userInfo(tier1);
        assertEq(ref, root); // tier1's parent is root.
        assertEq(gen, 1); // tier1's generation is 1.
    }

    // Quick register function.
    function _register(uint parentKey, uint childKey) internal {
        _register(parentKey, childKey, onceSigKey++, block.timestamp + 1);
    }

    // This function is meant to be mapped with register() in ForeignAgency.sol.
    function _register(uint parentKey, uint childKey, uint onceKey, uint deadline) private {
        address onceAddr = vm.addr(onceKey);
        address child = vm.addr(childKey);

        // parent sign parentSig
        bytes32 digest = _getHashTypedData(
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                REGISTER_PARENT_TYPEHASH,
                onceAddr,
                deadline,
                0
            )
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(parentKey, digest);
        bytes memory parentSig = abi.encodePacked(r, s, v);

        // child sign onceSig
        digest = _getHashTypedData(
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                REGISTER_ONCE_TYPEHASH,
                child
            )
        ));
        (v, r, s) = vm.sign(onceKey, digest);
        bytes memory onceSig = abi.encodePacked(r, s, v);

        // child call register
        vm.prank(child);
        agency.register(parentSig, onceSig, deadline);
    }

    // This function will construct a full tree that all nodes have three child.
    function _registerFullTree(uint gen) internal {        
        uint parentId;
        uint childId = 5;
        for (uint i = 2; i <= gen; i++) {
            skip(4 hours);
            for (uint j = 0; j < 3**i; j++) {
                parentId = (childId + 1) / 3;
                _register(parentId, childId);
                childId++;
            }
        }
    }
    
    function _getHashTypedData(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}