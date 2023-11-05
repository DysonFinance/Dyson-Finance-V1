// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../DYSON.sol";
import "../sDYSON.sol";
import "../Factory.sol";
import "../Pair.sol";
import "../Router.sol";
import "../util/AddressBook.sol";
import "../util/TokenSender.sol";
import "interface/IERC20.sol";
import "./Addresses.sol";
import "forge-std/Test.sol";

contract MainnetDeployScriptPart1 is Addresses, Test {
    DYSON public dyson;
    sDYSON public sDyson;
    Factory public factory;
    Router public router;
    AddressBook public addressBook; 
    TokenSender public tokenSender;
    Pair public weth_usdc_pair;

    // Configs for Router
    address weth = getAddress("WETH");
    address usdc = getAddress("USDC");
    address wbtc = getAddress("WBTC");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        console.log("%s: %s", "weth", address(weth));

        // ------------ Deploy all contracts ------------
        // Deploy TokenSender 
        tokenSender = new TokenSender();

        // Deploy Dyson, sDyson, Factory and Router
        dyson = new DYSON(deployer);
        sDyson = new sDYSON(deployer, address(dyson));
        factory = new Factory(deployer);
        router = new Router(address(weth), deployer, address(factory), address(sDyson), address(dyson));

        // Create pairs
        weth_usdc_pair = Pair(factory.createPair(address(weth), address(usdc)));

        // Deploy AddressBook
        addressBook = new AddressBook(deployer);

        // ------------ Setup configs ------------
        addressBook.file("govToken", address(dyson));
        addressBook.file("govTokenStaking", address(sDyson));
        addressBook.file("factory", address(factory));
        addressBook.file("router", address(router));
        addressBook.setCanonicalIdOfPair(address(weth), address(usdc), 1);

        // rely token to router
        router.rely(address(weth), address(weth_usdc_pair), true); // WETH for weth_usdc_pair
        router.rely(address(usdc), address(weth_usdc_pair), true); // USDC for weth_usdc_pair

        setAddress(address(addressBook), "addressBook");
        setAddress(address(dyson), "DYSON");
        setAddress(address(sDyson), "sDYSON");
        setAddress(address(factory), "factory");
        setAddress(address(router), "router");
        setAddress(address(weth_usdc_pair), "wethUsdcPair");
        setAddress(address(tokenSender), "tokenSender");

        console.log("%s", "done");
        
        console.log("{");
        console.log("\"%s\": \"%s\",", "addressBook", address(addressBook));
        console.log("\"%s\": \"%s\",", "wrappedNativeToken", address(weth));
        console.log("\"%s\": \"%s\",", "dyson", address(dyson));
        console.log("\"%s\": \"%s\",", "pairFactory", address(factory));
        console.log("\"%s\": \"%s\",", "router", address(router));
        console.log("\"%s\": \"%s\",", "sDyson", address(sDyson));
        console.log("\"tokens\": {");
        console.log("\"%s\": \"%s\",", "WETH", address(weth));
        console.log("\"%s\": \"%s\"", "USDC", address(usdc));
        console.log("},");
        console.log("\"baseTokenPair\": {");
        console.log("\"%s\": \"%s\"", "wethUsdcPair", address(weth_usdc_pair));
        console.log("},");
        console.log("\"other\": {");
        console.log("\"%s\": \"%s\"", "tokenSender", address(tokenSender));
        console.log("}");
        console.log("}");

        vm.stopBroadcast();
    }

}