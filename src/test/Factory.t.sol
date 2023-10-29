// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./TestUtils.sol";
import "src/Factory.sol";
import "src/DYSON.sol";
import "src/sDYSON.sol";

contract FarmMock {}

contract FactoryTest is TestUtils {
    address testOwner = address(this);
    address token0 = address(new DYSON(testOwner));
    address token1 = address(new DYSON(testOwner));
    address token2 = address(new DYSON(testOwner));
    address gov = address(new DYSON(testOwner));
    address sGov = address(new sDYSON(testOwner, gov));
    address farm = address(new FarmMock());
    
    Factory factory;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");

    function setUp() public {
        factory = new Factory(testOwner);
    }

    function testCreatePair() public {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        address pair01 = factory.createPair(token0, token1);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair01);
        assertEq(factory.getPairCount(token0, token1), 1);

        address pair12 = factory.createPair(token1, token2);
        assertEq(factory.allPairsLength(), 2);
        assertEq(factory.allPairs(1), pair12);
        assertEq(factory.getPairCount(token0, token1), 1);
        assertEq(factory.getPairCount(token1, token2), 1);

        address pair10 = factory.createPair(token1, token0);
        assertEq(factory.allPairsLength(), 3);
        assertEq(factory.allPairs(2), pair10);
        assertEq(factory.getPairCount(token0, token1), 2);
        assertEq(factory.getPair(token0, token1, 0), pair01);
        assertEq(factory.getPair(token0, token1, 1), pair10);
    }

    function testCannotCreateByNonController() public {
        vm.startPrank(alice);
        vm.expectRevert("forbidden");
        factory.createPair(token0, token1);
    }

    function testSetController() public {
        factory.setController(alice);
        vm.prank(alice);
        factory.becomeController();
        assertEq(factory.controller(), alice);
    }
}