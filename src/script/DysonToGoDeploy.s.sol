// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "interface/IPair.sol";
import "../DysonToGo.sol";
import "../util/AddressBook.sol";
import "./Addresses.sol";
import "forge-std/Test.sol";

contract DysonToGoDeployScript is Addresses, Test {

    function run() external {
        uint256 toGoFactoryController = vm.envUint("TOGO_FACTORY_CONTROLLER_PRIVATEKEY");
        vm.startBroadcast(toGoFactoryController);

        DysonToGoFactory toGoFactory = DysonToGoFactory(getAddress("dysonToGoFactory"));
        address teacher = getAddress("teacherAddress");
        address addressBook = getAddress("addressBook");
        address[] memory gauges = getRelyNeededAddresses(".relyGauges");
        address[] memory pairs = getRelyNeededAddresses(".relyPairs");
        address dyson = AddressBook(addressBook).govToken();

        // Deploy DysonToGo
        DysonToGo toGo = DysonToGo(payable(toGoFactory.createDysonToGo(teacher)));
        address sDyson = toGo.sDYSON();

        // rely each token for pairs
        for(uint i=0; i < pairs.length; i++) {
            address pair = pairs[i];
            address token0 = IPair(pair).token0();
            address token1 = IPair(pair).token1();
            if (token0 == dyson) toGo.relyDysonPair(token1, 1, true);
            else toGo.rely(token0, pair, true);
            if (token1 == dyson) toGo.relyDysonPair(token0, 1, true);
            else toGo.rely(token1, pair, true);
        }

        // rely sDYSON for gauges
        for(uint i=0; i < gauges.length; i++) {
            toGo.rely(sDyson, gauges[i], true);
        }
        
        console.log("{");
        console.log("\"%s\": \"%s\",", "toGo", address(toGo));
        console.log("}");

        vm.stopBroadcast();
    }
}