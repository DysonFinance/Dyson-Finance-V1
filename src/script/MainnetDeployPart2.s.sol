// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../Agency.sol";
import "../DYSON.sol";
import "../sDYSON.sol";
import "../Factory.sol";
import "../GaugeFactory.sol";
import "../BribeFactory.sol";
import "../Pair.sol";
import "../Router.sol";
import "../Farm.sol";
import "../Gauge.sol";
import "../Bribe.sol";
import "../util/AddressBook.sol";
import "../util/TokenSender.sol";
import "../util/TreasuryVester.sol";
import "../util/FeeDistributor.sol";
import "interface/IERC20.sol";
import "./Addresses.sol";
import "forge-std/Test.sol";

contract MainnetDeployScriptPart2 is Addresses, Test {
    DYSON public dyson = DYSON(getAddress("DYSON"));
    sDYSON public sDyson = sDYSON(getAddress("sDYSON"));
    Factory public factory = Factory(getAddress("factory"));
    Router public router = Router(payable(getAddress("router")));
    AddressBook public addressBook = AddressBook(getAddress("addressBook"));
    TokenSender public tokenSender = TokenSender(getAddress("tokenSender"));
    Pair public weth_usdc_pair = Pair(getAddress("wethUsdcPair"));
    address public vesterRecipient = getAddress("vesterRecipient");

    // Configs for Router
    address weth = getAddress("WETH");
    address usdc = getAddress("USDC");
    address wbtc = getAddress("WBTC");

    Agency public agency;
    GaugeFactory public gaugeFactory;
    BribeFactory public bribeFactory;
    StakingRateModel public rateModel;
    Farm public farm;
    TreasuryVester public vester;
    address public wethFeeDistributor;
    address public wbtcFeeDistributor;
    address public dysnFeeDistributor;
    address public dysonGauge;
    address public dysonBribe;
    address public wethGauge;
    address public wethBribe; 
    address public wbtcGauge;
    address public wbtcBribe;

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

    // Fee rate to DAO wallet
    uint public feeRateToDao = 0.5e18;

    // TreasuryVester configs
    uint public vestingBegin = block.timestamp + 100;
    uint public vestingCliff = vestingBegin + 86400; // 1 day
    uint public vestingEnd = vestingCliff + 86400 * 2; // 2 days
    uint public vestingAmount = 1000e18; // 1000 DYSN

    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        console.log("%s: %s", "weth", address(weth));

        // ------------ Deploy all contracts ------------
        // Deploy TreasuryVester 
        vester = new TreasuryVester(address(dyson), vesterRecipient, vestingAmount, vestingBegin, vestingCliff, vestingEnd);

        // Deploy Agency
        agency = new Agency(deployer, owner);

        // Deploy GaugeFactory and BribeFactory
        gaugeFactory = new GaugeFactory(deployer);
        bribeFactory = new BribeFactory(deployer);

        // Deploy StakingRateModel
        rateModel = new StakingRateModel(initialRate);

        // Deploy Farm
        farm = new Farm(deployer, address(agency), address(dyson));

        // Create pairs
        dysn_usdc_pair = Pair(factory.createPair(address(dyson), address(usdc)));
        wbtc_usdc_pair = Pair(factory.createPair(address(wbtc), address(usdc)));

        // Deploy Gauges and Bribes
        dysonGauge = gaugeFactory.createGauge(address(farm), address(sDyson), address(dysn_usdc_pair), WEIGHT_DYSN, BASE, SLOPE);
        dysonBribe = bribeFactory.createBribe(dysonGauge);
        
        wethGauge = gaugeFactory.createGauge(address(farm), address(sDyson), address(weth_usdc_pair), WEIGHT_WETH, BASE, SLOPE);
        wethBribe = bribeFactory.createBribe(wethGauge);
        
        wbtcGauge = gaugeFactory.createGauge(address(farm), address(sDyson), address(wbtc_usdc_pair), WEIGHT_WBTC, BASE, SLOPE);
        wbtcBribe = bribeFactory.createBribe(wbtcGauge);

        wethFeeDistributor = address(new FeeDistributor(owner, address(weth_usdc_pair), address(wethBribe), owner, feeRateToDao));
        wbtcFeeDistributor = address(new FeeDistributor(owner, address(wbtc_usdc_pair), address(wbtcBribe), owner, feeRateToDao));
        dysnFeeDistributor = address(new FeeDistributor(owner, address(dysn_usdc_pair), address(dysonBribe), owner, feeRateToDao));

        // ------------ Setup configs ------------
        // Setup minters
        dyson.addMinter(address(farm));

        // Set feeTo
        weth_usdc_pair.setFeeTo(wethFeeDistributor);   
        wbtc_usdc_pair.setFeeTo(wbtcFeeDistributor);
        dysn_usdc_pair.setFeeTo(dysnFeeDistributor);  
        
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

        addressBook.file("farm", address(farm));
        addressBook.file("agentNFT", address(agency.agentNFT()));
        addressBook.file("agency", address(agency));
        addressBook.setBribeOfGauge(address(dysonGauge), address(dysonBribe));
        addressBook.setBribeOfGauge(address(wbtcGauge), address(wbtcBribe));
        addressBook.setBribeOfGauge(address(wethGauge), address(wethBribe));
        addressBook.setCanonicalIdOfPair(address(dyson), address(usdc), 1);
        addressBook.setCanonicalIdOfPair(address(wbtc), address(usdc), 1);

        // rely token to router
        router.rely(address(wbtc), address(wbtc_usdc_pair), true); // WBTC for wbtc_usdc_pair
        router.rely(address(usdc), address(wbtc_usdc_pair), true); // USDC for wbtc_usdc_pair
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

        // Owner need to call 'factory.becomeController();'

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
        console.log("},");
        console.log("\"other\": {");
        console.log("\"%s\": \"%s\",", "dysn_usdc_gauge", address(dysonGauge));
        console.log("\"%s\": \"%s\",", "dysn_usdc_bribe", address(dysonBribe));
        console.log("\"%s\": \"%s\",", "wbtc_usdc_gauge", address(wbtcGauge));
        console.log("\"%s\": \"%s\",", "wbtc_usdc_bribe", address(wbtcBribe));
        console.log("\"%s\": \"%s\",", "weth_usdc_gauge", address(wethGauge));
        console.log("\"%s\": \"%s\",", "weth_usdc_bribe", address(wethBribe));
        console.log("\"%s\": \"%s\",", "dysn_usdc_feeDistributor", address(dysnFeeDistributor));
        console.log("\"%s\": \"%s\",", "wbtc_usdc_feeDistributor", address(wbtcFeeDistributor));
        console.log("\"%s\": \"%s\",", "weth_usdc_feeDistributor", address(wethFeeDistributor));
        console.log("\"%s\": \"%s\",", "treasuryVester", address(vester));
        console.log("\"%s\": \"%s\",", "treasuryVesterRecipient", address(vesterRecipient));
        console.log("\"%s\": \"%s\"", "tokenSender", address(tokenSender));
        console.log("}");
        console.log("}");

        vm.stopBroadcast();
    }

}