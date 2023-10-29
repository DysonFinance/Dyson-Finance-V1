// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import 'src/Agency.sol';

contract AgencyTest is Test {
    uint public constant rootKey = 1;
    address public root = vm.addr(1);
    address public testOwner = address(this);
    address public controller = vm.addr(100);
    uint[] public adminKeys = [2, 3, 4];
    address[] public tier1s = [vm.addr(2), vm.addr(3), vm.addr(4)];
    uint onceSigKey = 66666;
    Agency agency = new Agency(address(this), root);
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
    uint public constant TRANSFER_CD = 60000;

    // The state of the contract gets reset before each
    // test is run, with the `setUp()` function being called
    // each time after deployment.
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

    function testIDs() public {
        // Check root ID
        assertEq(agency.whois(root), 1);
        assertEq(agentNFT.balanceOf(root), 1);
        assertEq(agentNFT.ownerOf(1), root);
        // Check others' ID
        for (uint i = 2; i < 14; ++i) {
            address owner = vm.addr(i);
            uint tokenId = i;
            assertEq(agency.whois(owner), i);
            assertEq(agentNFT.balanceOf(owner), 1);
            assertEq(agentNFT.ownerOf(tokenId), owner);
        }
    }

    function testParentChildConsistency() public {
        for (uint i = 0; i < 14; ++i) {
            _checkParentChildConsistency(i);
        }
    }

    function testGetTokenURI() public {
        uint notExistTokenId = 999;
        vm.expectRevert("token not exist");
        agentNFT.tokenURI(notExistTokenId);
        uint tokenId = 1;
        agentNFT.tokenURI(tokenId);
    }

    function testCannotMintByNonAgency() public {
        address user = address(5566);
        uint tokenId = 5566;
        vm.expectRevert("forbidden");
        agentNFT.onMint(user, tokenId);
    }

    function testCannotAdminAddByNonController() public {
        // Even tier1 can not add admin.
        address tier1 = tier1s[0];
        address newAgent = vm.addr(4);
        vm.prank(tier1);
        vm.expectRevert("forbidden");
        agency.adminAdd(newAgent);
    }

    function testCannotAdminAddZeroAddress() public {
        address newAgent = address(0);
        vm.expectRevert("new agent invalid address");
        agency.adminAdd(newAgent);
    }

    function testCannotAdminAddAlreadyRegisteredAddress() public {
        address tier1 = tier1s[0];
        vm.expectRevert("occupied");
        agency.adminAdd(tier1);

        // Check userInfo
        (address ref, uint gen) = agency.userInfo(tier1);
        assertEq(ref, root); // tier1's parent is root.
        assertEq(gen, 1); // tier1's generation is 1.
    }

    function testAdminAdd() public {
        uint nextNFTTokenId = agentNFT.totalSupply() + 1;
        address newAgent = address(5566);
        // Add new agent
        agency.adminAdd(newAgent);
        assertEq(agentNFT.balanceOf(newAgent), 1);
        assertEq(agentNFT.ownerOf(nextNFTTokenId), newAgent);
        (address ref, uint gen) = agency.userInfo(newAgent);
        assertEq(ref, root); // newAgent's parent is root.
        assertEq(gen, 1); // newAgent's generation is 1.
    }

    function testAdminAddByController() public {
        uint nextNFTTokenId = agentNFT.totalSupply() + 1;
        address newAgent = address(5566);

        vm.prank(controller);
        agency.adminAdd(newAgent);
        assertEq(agentNFT.balanceOf(newAgent), 1);
        assertEq(agentNFT.ownerOf(nextNFTTokenId), newAgent);
        (address ref, uint gen) = agency.userInfo(newAgent);
        assertEq(ref, root); // newAgent's parent is root.
        assertEq(gen, 1); // newAgent's generation is 1.
    }

    function testCannotApproveNotExistToken() public {
        uint notExistTokenId = 999;
        address to = address(5566);
        vm.expectRevert("token not exist");
        agentNFT.approve(to, notExistTokenId);
    }

    function testApproveNFTToken() public {
        address to = address(5566);
        uint tokenId = 1;
        assertEq(agentNFT.getApproved(tokenId), address(0));
        vm.prank(root);
        agentNFT.approve(to, tokenId);
        assertEq(agentNFT.getApproved(tokenId), to);
    }

    function testApproveForAllNFTToken() public {
        address approver = address(1234);
        address operator = address(5566);
        assertEq(agentNFT.isApprovedForAll(approver, operator), false);
        vm.prank(approver);
        agentNFT.setApprovalForAll(operator, true);
        assertEq(agentNFT.isApprovedForAll(approver, operator), true);
    }

    function testCannotTransferToRegisteredAccount() public {
        // vm.addr(7) is already registered
        address from = vm.addr(6);
        address to = vm.addr(7);
        uint fromId = agency.whois(from);
        assertEq(agency.whois(to), agency.whois(to));
        vm.prank(from);
        vm.expectRevert("occupied");
        agentNFT.transferFrom(from, to, fromId);
    }

    function testCannotTransferFromUnregisteredAccount() public {
        // vm.addr(17) has not registered
        address from = vm.addr(17);
        address to = address(5566);
        uint fromId = agency.whois(from);
        assertEq(fromId, 0);
        vm.prank(from);
        vm.expectRevert("nothing to transfer");
        agentNFT.transferFrom(from, to, fromId);
    }

    function testCannotTransferAccountNotOwned() public {
        address from = vm.addr(4);
        address other = vm.addr(5);
        address to = address(5566);
        uint otherId = agency.whois(other);
        vm.prank(from);
        vm.expectRevert("forbidden");
        agentNFT.transferFrom(from, to, otherId);
    }

    function testCannotTransferToZeroAddress() public {
        address from = vm.addr(4);
        address to = address(0);
        uint fromId = agency.whois(from);
        vm.prank(from);
        vm.expectRevert("transfer invalid address");
        agentNFT.transferFrom(from, to, fromId);
    }

    function testCannotTransferViaAgencyContract() public {
        address from = vm.addr(4);
        address to = address(5566);
        uint fromId = agency.whois(from);
        vm.prank(from);
        vm.expectRevert("forbidden");
        agency.transfer(from, to, fromId);
    }

    function testTransfer() public {
        address from = vm.addr(5);
        address to = address(5566);
        uint fromNFTTokenIdBefore = 5;
        uint fromIdBefore = agency.whois(from);
        (address fromRefBefore, uint fromGenBefore) = agency.userInfo(from);

        vm.prank(from);
        agentNFT.transferFrom(from, to, fromIdBefore);

        assertEq(agentNFT.balanceOf(from), 0);
        assertEq(agentNFT.balanceOf(to), 1);
        assertEq(agentNFT.ownerOf(fromNFTTokenIdBefore), to);
        assertEq(agency.whois(from), 0);
        assertEq(agency.whois(to), fromIdBefore);
        (address toRef, uint toGen) = agency.userInfo(to);
        assertEq(fromRefBefore, toRef);
        assertEq(fromGenBefore, toGen);
        _checkParentChildConsistency(fromIdBefore);
    }

    function testTransferWhenCooldown() public {
        address from = vm.addr(5);
        address to = address(5566);
        address to2 = address(1234);
        uint fromNFTTokenIdBefore = 5;
        uint fromIdBefore = agency.whois(from);
        (address fromRefBefore, uint fromGenBefore) = agency.userInfo(from);
        
        uint fromId = agency.whois(from);
        vm.prank(from);
        agentNFT.transferFrom(from, to, fromId);
        skip((fromGenBefore + 1) * TRANSFER_CD + 1);
        vm.prank(to);
        agentNFT.transferFrom(to, to2, fromId);

        assertEq(agentNFT.balanceOf(from), 0);
        assertEq(agentNFT.balanceOf(to), 0);
        assertEq(agentNFT.balanceOf(to2), 1);
        assertEq(agentNFT.ownerOf(fromNFTTokenIdBefore), to2);
        assertEq(agency.whois(from), 0);
        assertEq(agency.whois(to), 0);
        assertEq(agency.whois(to2), fromIdBefore);
        (address toRef, uint toGen) = agency.userInfo(to2);
        assertEq(fromRefBefore, toRef);
        assertEq(fromGenBefore, toGen);
        _checkParentChildConsistency(fromIdBefore);
    }

    function testCannotTransferWhenNotCooldown() public {
        address from = vm.addr(5);
        address to = address(5566);
        address to2 = address(1234);
        (, uint fromGenBefore) = agency.userInfo(from);
        
        uint fromId = agency.whois(from);
        vm.prank(from);
        agentNFT.transferFrom(from, to, fromId);
        skip((fromGenBefore + 1) * TRANSFER_CD - 1);
        vm.prank(to);
        vm.expectRevert(bytes("cd"));
        agentNFT.transferFrom(to, to2, fromId);
    }

    function testCannotTransferWithoutApproval() public {
        address from = vm.addr(4);
        address to = address(5566);
        address other = address(1234);
        uint fromId = agency.whois(from);
        vm.prank(other);
        vm.expectRevert("forbidden");
        agentNFT.transferFrom(from, to, fromId);
    }

    function testNFTTransferFrom() public {
        address from = vm.addr(5);
        address to = address(5566);
        address other = address(1234);
        uint fromNFTTokenIdBefore = 5;
        uint fromIdBefore = agency.whois(from);

        vm.prank(from);
        agentNFT.approve(other, fromIdBefore);
        assertEq(agentNFT.getApproved(fromIdBefore), other);

        vm.prank(other);
        agentNFT.transferFrom(from, to, fromIdBefore);

        assertEq(agentNFT.getApproved(fromIdBefore), address(0));
        assertEq(agentNFT.balanceOf(from), 0);
        assertEq(agentNFT.balanceOf(to), 1);
        assertEq(agentNFT.ownerOf(fromNFTTokenIdBefore), to);
        assertEq(agency.whois(from), 0);
    }

    function testTransferRoot() public {
        address from = root;
        address to = address(5566);
        uint fromIdBefore = agency.whois(from);
        (, uint fromGenBefore) = agency.userInfo(from);

        vm.prank(from);
        agentNFT.transferFrom(from, to, fromIdBefore);

        assertEq(agency.whois(from), 0);
        assertEq(agency.whois(to), fromIdBefore);
        (address toRef, uint toGen) = agency.userInfo(to);
        assertEq(toRef, to); // Root's parent is root itself so its parent's owner is also root's owner
        assertEq(fromGenBefore, toGen);
        _checkParentChildConsistency(fromIdBefore);
    }

    function testTransferFuzzing(uint fromKey, uint toKey) public {
        uint MAX_PRIVATE_KEY = 115792089237316195423570985008687907852837564279074904382605163141518161494336;
        vm.assume(fromKey < MAX_PRIVATE_KEY && fromKey > 0);
        vm.assume(toKey < MAX_PRIVATE_KEY && toKey > 0);

        address from = vm.addr(fromKey);
        address to = vm.addr(toKey);
        uint fromId = agency.whois(from);
        uint toId = agency.whois(to);

        vm.prank(from);
        if (fromId == 0) {
            vm.expectRevert("nothing to transfer");
            agentNFT.transferFrom(from, to, fromId);
        } else if (toId != 0) {
            vm.expectRevert("occupied");
            agentNFT.transferFrom(from, to, fromId);
        } else {
            agentNFT.transferFrom(from, to, fromId);
            assertEq(agency.whois(from), 0);
            assertEq(agency.whois(to), fromId);
            _checkParentChildConsistency(fromId);
        }  
    }

    function testCannotRegisterAlreadyRegisteredAccount() public {
        vm.expectRevert("already registered");
        _register(5, 6);
    }

    function testCannotReuseRegisterSignature() public {
        uint oldOnceSigKey = onceSigKey;
        _register(5, 14);
        vm.expectRevert("signature is used");
        _register(5, 15, oldOnceSigKey, block.timestamp + 1);
    }

    function testCannotRegisterIfSlotsFull() public {
        _register(5, 14);
        _register(5, 15);
        _register(5, 16);
        vm.expectRevert("no empty slot");
        _register(5, 17);
    }

    function testCannotRegisterIfExpired() public {
        uint oldDeadline = block.timestamp + 1;
        skip(1 hours);
        vm.expectRevert("exceed deadline");
        _register(6, 17, onceSigKey, oldDeadline);
    }
    
    function testRegisterCoolDown() public {
        // Register new account vm.addr(14)
        _register(5, 14);

        // Register new account under vm.addr(14) should fail before cooldown ends
        skip(4 hours - 1); // 4 hour - 1
        vm.expectRevert("not ready");
        _register(14, 15);
        skip(1);
        // Should succeed now
        _register(14, 15);

        // Register new account under vm.addr(15) should fail before cooldown ends
        vm.expectRevert("not ready");
        _register(15, 16);
        skip(4 hours);
        // Should succeed now
        _register(15, 16);

        _checkParentChildConsistency(15);
        _checkParentChildConsistency(16);
    }

    function testRegisterSigFuzzing(uint parentKey, uint childKey) public {
        // Make sure key does not exceed maximum.
        uint MAX_PRIVATE_KEY = 115792089237316195423570985008687907852837564279074904382605163141518161494336;
        vm.assume(parentKey < MAX_PRIVATE_KEY && parentKey > 0);
        vm.assume(childKey < MAX_PRIVATE_KEY && childKey > 0);
        skip(4 hours);

        bool isParentRegistered = _isRegistered(parentKey);
        bool isChildRegistered = _isRegistered(childKey);

        if (isChildRegistered) {
            // Both parent and child are registered.
            vm.expectRevert("already registered");
            _register(parentKey, childKey);
        }
        else if (!isParentRegistered) {
            // Parent is not registered.
            vm.expectRevert("invalid parent");
            _register(parentKey, childKey);
        }
        else {
            uint parentId = agency.whois(vm.addr(parentKey));
            (, , , , uint[] memory curChild) = agency.getAgent(parentId);
            if (curChild.length >= 3) {
                vm.expectRevert("no empty slot");
            }
            _register(parentKey, childKey);
            _checkParentChildConsistency(parentId);
        }
    }

    // Quick register function.
    function _register(uint parentKey, uint childKey) internal {
        _register(parentKey, childKey, onceSigKey++, block.timestamp + 1);
    }

    // This function is meant to be mapped with register() in Agency.sol.
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

    function _isRegistered(uint key) internal view returns (bool) {
        return (agency.whois(vm.addr(key)) > 0);
    }

    function _printAgent(address agent) internal view {
        (address owner, uint gen, uint birth, uint parentId, ) = agency.getAgent(agency.whois(agent));
        (address parent, , , ,) = agency.getAgent(parentId);
        console.log("----------------------------");
        console.log("Agent", agent);
        console.log("AgentId", agency.whois(agent));
        console.log("Owner", owner);
        console.log("Gen", gen);
        console.log("Birth", birth);
        console.log("ParentId", parentId);
        console.log("Parent", parent);
        console.log("----------------------------");
    }

    function _checkParentChildConsistency(uint id) private {
        (, uint parentGen, , , uint[] memory childrenId) = agency.getAgent(id);
        for (uint i = 0; i < childrenId.length; ++i) {
            (, uint childGen, , uint parentId, ) = agency.getAgent(childrenId[i]);
            assertEq(parentId, id);
            assertEq(childGen, parentGen + 1);
        }
    }
}