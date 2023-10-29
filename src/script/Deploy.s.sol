// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../Agency.sol";
import "../DYSON.sol";
import "../sDYSON.sol";
import "../Factory.sol";
import "../Router.sol";
import "../Farm.sol";
import "./Addresses.sol";

contract DeployScript is Addresses, Test {
    Agency public agency;
    DYSON public dyson;
    sDYSON public sDyson;
    Factory public factory;
    Router public router;
    StakingRateModel public rateModel;
    Farm public farm;

    // Configs for Agency
    address root = address(0x5566);
    // Configs for Router
    address weth = getAddress("WETH");
    // Configs for StakingRateModel
    uint initialRate = 0.0625e18;

    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Agency, Dyson
        agency = new Agency(owner, root);
        dyson = new DYSON(owner);

        // Deploy StakingRateModel and sDYSON
        rateModel = new StakingRateModel(0.0625e18);
        sDyson = new sDYSON(deployer, address(dyson));

        // Deploy Factory and Router
        factory = new Factory(owner);
        router = new Router(weth, owner, address(factory), address(sDyson), address(dyson));

        // Setup sDYSON
        sDyson.setStakingRateModel(address(rateModel));
        sDyson.transferOwnership(owner);

        // Deploy Farm
        farm = new Farm(owner, address(agency), address(dyson));

        vm.stopBroadcast();
    }
}