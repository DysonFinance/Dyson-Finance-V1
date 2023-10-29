// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../Agency.sol";
import "../DYSON.sol";
import "../sDYSON.sol";
import "../Factory.sol";
import "../Pair.sol";
import "../Router.sol";
import "../Farm.sol";
import "../Gauge.sol";
import "../Bribe.sol";
import "../util/AddressBook.sol";
import "../util/TokenSender.sol";
import "interface/IERC20.sol";
import "./Addresses.sol";
import "forge-std/Test.sol";

contract MainnetDeployScript is Addresses, Test {
    Agency public agency;
    DYSON public dyson;
    sDYSON public sDyson;
    Factory public factory;
    Router public router;
    StakingRateModel public rateModel;
    Farm public farm;
    AddressBook public addressBook; 
    TokenSender public tokenSender;

    Pair public weth_usdc_pair;
    Pair public wbtc_usdc_pair;
    Pair public dysn_usdc_pair;

    uint constant WEIGHT_DYSN = 102750e12; // sqrt(1250000e6*5000000e18) * 0.00274 *15
    uint constant WEIGHT_WETH = 1284e12; // ETH price = 1600USD, so W = sqrt(1250000e6*781e18) * 0.00274 *15
    uint constant WEIGHT_WBTC = 325e7; // BTC price = 25000USD, so W = sqrt(1250000e6*50e8) * 0.00274 *15
    uint constant BASE = 0; // 0.17e18; // 0.5 / 3
    uint constant SLOPE = 0.00000009e18;
    uint constant GLOBALRATE = 0; // 0.951e18;
    uint constant GLOBALWEIGHT = 821917e18;

    // Configs for StakingRateModel
    uint initialRate = 0.0625e18;

    // Configs for Router
    address weth = getAddress("WETH");
    address usdc = getAddress("USDC");
    address wbtc = getAddress("WBTC");

    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        console.log("%s: %s", "weth", address(weth));

        // ------------ Deploy all contracts ------------

        // Deploy TokenSender 
        tokenSender = new TokenSender();

        // Deploy Agency
        agency = new Agency(deployer, owner);
        console.log("%s: %s", "agency", address(agency));

        // Deploy Dyson, sDyson, Factory and Router
        dyson = new DYSON(deployer);
        sDyson = new sDYSON(deployer, address(dyson));
        factory = new Factory(deployer);
        router = new Router(address(weth), deployer, address(factory), address(sDyson), address(dyson));
        console.log("%s: %s", "dyson", address(dyson));
        console.log("%s: %s", "sDyson", address(sDyson));
        console.log("%s: %s", "factory", address(factory));
        console.log("%s: %s", "router", address(router));

        // Deploy StakingRateModel
        rateModel = new StakingRateModel(initialRate);
        console.log("%s: %s", "rateModel", address(rateModel));

        // Deploy Farm
        farm = new Farm(deployer, address(agency), address(dyson));
        console.log("%s: %s", "farm", address(farm));

        // Create pairs
        dysn_usdc_pair = Pair(factory.createPair(address(dyson), address(usdc)));
        weth_usdc_pair = Pair(factory.createPair(address(weth), address(usdc)));
        wbtc_usdc_pair = Pair(factory.createPair(address(wbtc), address(usdc)));
        console.log("%s: %s", "dysn_usdc_pair", address(dysn_usdc_pair));
        console.log("%s: %s", "weth_usdc_pair", address(weth_usdc_pair));
        console.log("%s: %s", "wbtc_usdc_pair", address(wbtc_usdc_pair));

        // Deploy Gauges and Bribes
        address dysonGauge = address(new Gauge(address(farm), address(sDyson), address(dysn_usdc_pair), WEIGHT_DYSN, BASE, SLOPE));
        address dysonBribe = address(new Bribe(dysonGauge));
        console.log("%s: %s", "dysn_usdc_pair gauge", address(dysonGauge));
        console.log("%s: %s", "dysn_usdc_pair bribe", address(dysonBribe));

        address wethGauge = address(new Gauge(address(farm), address(sDyson), address(weth_usdc_pair), WEIGHT_WETH, BASE, SLOPE));
        address wethBribe = address(new Bribe(wethGauge));
        console.log("%s: %s", "weth_usdc_pair gauge", address(wethGauge));
        console.log("%s: %s", "weth_usdc_pair bribe", address(wethBribe));

        address wbtcGauge = address(new Gauge(address(farm), address(sDyson), address(wbtc_usdc_pair), WEIGHT_WBTC, BASE, SLOPE));
        address wbtcBribe = address(new Bribe(wbtcGauge));
        console.log("%s: %s", "wbtc_usdc_pair gauge", address(wbtcGauge));
        console.log("%s: %s", "wbtc_usdc_pair bribe", address(wbtcBribe));

        // Deploy AddressBook
        addressBook = new AddressBook(deployer);

        // ------------ Setup configs ------------
        // Setup minters
        dyson.addMinter(address(farm));
        
        // Setup sDyson
        sDyson.setStakingRateModel(address(rateModel));
        sDyson.transferOwnership(owner);

        // Setup farm
        dysn_usdc_pair.setFarm(address(farm));
        weth_usdc_pair.setFarm(address(farm));
        wbtc_usdc_pair.setFarm(address(farm));

        // Setup gauge and bribe
        farm.setPool(address(dysn_usdc_pair), dysonGauge);
        farm.setPool(address(weth_usdc_pair), wethGauge);
        farm.setPool(address(wbtc_usdc_pair), wbtcGauge);

        // Setup global reward rate
        farm.setGlobalRewardRate(GLOBALRATE, GLOBALWEIGHT);

        addressBook.file("govToken", address(dyson));
        addressBook.file("govTokenStaking", address(sDyson));
        addressBook.file("factory", address(factory));
        addressBook.file("router", address(router));
        addressBook.file("farm", address(farm));
        addressBook.file("agentNFT", address(agency.agentNFT()));
        addressBook.file("agency", address(agency));
        addressBook.setBribeOfGauge(address(dysonGauge), address(dysonBribe));
        addressBook.setBribeOfGauge(address(wbtcGauge), address(wbtcBribe));
        addressBook.setBribeOfGauge(address(wethGauge), address(wethBribe));
        addressBook.setCanonicalIdOfPair(address(dyson), address(usdc), 1);
        addressBook.setCanonicalIdOfPair(address(wbtc), address(usdc), 1);
        addressBook.setCanonicalIdOfPair(address(weth), address(usdc), 1);

        // rely token to router
        router.rely(address(wbtc), address(wbtc_usdc_pair), true); // WBTC for wbtc_usdc_pair
        router.rely(address(usdc), address(wbtc_usdc_pair), true); // USDC for wbtc_usdc_pair
        router.rely(address(weth), address(weth_usdc_pair), true); // WETH for weth_usdc_pair
        router.rely(address(usdc), address(weth_usdc_pair), true); // USDC for weth_usdc_pair
        router.rely(address(dyson), address(dysn_usdc_pair), true); // DYSN for dysn_usdc_pair
        router.rely(address(usdc), address(dysn_usdc_pair), true); // USDC for dysn_usdc_pair
        router.rely(address(sDyson), address(dysonGauge), true);
        router.rely(address(sDyson), address(wbtcGauge), true);
        router.rely(address(sDyson), address(wethGauge), true);
        router.rely(address(dyson), address(sDyson), true);

        // transfer ownership
        addressBook.file("owner", owner);
        agency.transferOwnership(owner);
        dyson.transferOwnership(owner);
        factory.setController(owner);
        farm.transferOwnership(owner);
        router.transferOwnership(owner);

        // --- After deployment, we need to config the following things: ---
        // Fund DYSON & USDC to dysn_usdc_pair
        // Fund WBTC & USDC to wbtc_usdc_pair
        // Fund WETH & USDC to weth_usdc_pair

        // dyson.transfer(address(dysn_usdc_pair), amount);
        // usdc.transfer(address(dysn_usdc_pair), amount);
        // wbtc.transfer(address(wbtc_usdc_pair), amount);
        // usdc.transfer(address(wbtc_usdc_pair), amount);
        // weth.deposit{value : 1 ether}();
        // weth.transfer(address(weth_usdc_pair), 1 ether);
        // usdc.mint(address(weth_usdc_pair), 1600e6); // 1600 usdc

        // Owner become the controller of factory
        // factory.becomeController();

        console.log("%s", "done");
        
        console.log("{");
        console.log("\"%s\": \"%s\",", "addressBook", address(addressBook));
        console.log("\"%s\": \"%s\",", "wrappedNativeToken", address(weth));
        console.log("\"%s\": \"%s\",", "agency", address(agency));
        console.log("\"%s\": \"%s\",", "dyson", address(dyson));
        console.log("\"%s\": \"%s\",", "pairFactory", address(factory));
        console.log("\"%s\": \"%s\",", "router", address(router));
        console.log("\"%s\": \"%s\",", "sDyson", address(sDyson));
        console.log("\"%s\": \"%s\",", "farm", address(farm));
        console.log("\"tokens\": {");
        console.log("\"%s\": \"%s\",", "WBTC", address(wbtc));
        console.log("\"%s\": \"%s\",", "WETH", address(weth));
        console.log("\"%s\": \"%s\"", "USDC", address(usdc));
        console.log("},");
        console.log("\"baseTokenPair\": {");
        console.log("\"%s\": \"%s\"", "dysonUsdcPair", address(dysn_usdc_pair));
        console.log("\"%s\": \"%s\",", "wbtcUsdcPair", address(wbtc_usdc_pair));
        console.log("\"%s\": \"%s\",", "wethUsdcPair", address(weth_usdc_pair));
        console.log("}");
        console.log("\"other\": {");
        console.log("%s: %s", "tokenSender", address(tokenSender));
        console.log("%s: %s", "dysnUsdcPairGauge", address(dysonGauge));
        console.log("%s: %s", "dysnUsdcPairBribe", address(dysonBribe));
        console.log("%s: %s", "wbtcUsdcPairGauge", address(wbtcGauge));
        console.log("%s: %s", "wbtcUsdcPairBribe", address(wbtcBribe));
        console.log("%s: %s", "wethUsdcPairGauge", address(wethGauge));
        console.log("%s: %s", "wethUsdcPairBribe", address(wethBribe));
        console.log("}");
        console.log("}");

        // Set addressBook address to deploy-config.json to feed DysonToGoFactoryDeploy.s.sol
        setAddress(address(addressBook), "addressBook");

        vm.stopBroadcast();
    }

}