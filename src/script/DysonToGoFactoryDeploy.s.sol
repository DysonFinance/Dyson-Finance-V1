// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "interface/IPair.sol";
import "../DysonToGo.sol";
import "../util/AddressBook.sol";
import "./Addresses.sol";
import "forge-std/Test.sol";

contract DysonToGoFactoryDeployScript is Addresses, Test {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address weth = getAddress("WETH");
        address addressBook = getAddress("addressBook");

        vm.startBroadcast(deployerPrivateKey);
        DysonToGoFactory toGoFactory = new DysonToGoFactory(deployer, weth, addressBook);

        console.log("{");
        console.log("\"%s\": \"%s\",", "toGoFactory", address(toGoFactory));
        console.log("}");

        // Set toGoFactory address to deploy-config.json to feed DysonToGoDeploy.s.sol
        setAddress(address(toGoFactory), "dysonToGoFactory");

        vm.stopBroadcast();
    }
}