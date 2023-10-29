// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../../script/Deploy.s.sol";
import "../../script/Addresses.sol";
import "../TestUtils.sol";

contract DeploymentTest is Addresses, TestUtils {
    DeployScript script;

    address root = address(0x5566);
    uint rootId = 1;
    address owner = vm.envAddress("OWNER_ADDRESS");
    address weth = getAddress("WETH");
    uint initialRate = 0.0625e18;

    function setUp() public {
        script = new DeployScript();
        script.run();
    }

    function testContractSetup() public {
        // Ownership check
        assertEq(script.agency().owner(), owner);
        assertEq(script.dyson().owner(), owner);
        assertEq(script.factory().controller(), owner);
        assertEq(script.router().owner(), owner);
        assertEq(script.sDyson().owner(), owner);
        assertEq(script.farm().owner(), owner);
        // Params check
        assertEq(script.agency().whois(root), rootId);
        assertEq(script.router().WETH(), weth);
        assertEq(address(script.sDyson().Dyson()), address(script.dyson()));
        assertEq(script.sDyson().currentModel().initialRate(), initialRate);
        assertEq(address(script.farm().agency()), address(script.agency()));
        assertEq(address(script.farm().gov()), address(script.dyson()));
    }
}