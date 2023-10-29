pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "./Agency.sol";
import "./Factory.sol";
import "./DYSON.sol";
import "./sDYSON.sol";
import "./Router.sol";
import "./Farm.sol";

contract Deploy {
    Agency public agency;
    Factory public factory;
    DYSON public dyson;
    sDYSON public sdyson;
    Router public router;
    StakingRateModel public rateModel;
    Farm public farm;

    constructor(address owner, address root, address weth) {
        agency = new Agency(owner, root);
        factory = new Factory(owner);
        dyson = new DYSON(owner);
        rateModel = new StakingRateModel(0.0625e18);
        sdyson = new sDYSON(address(this), address(dyson));
        sdyson.setStakingRateModel(address(rateModel));
        sdyson.transferOwnership(owner);
        router = new Router(weth, owner, address(factory), address(sdyson), address(dyson));
        farm = new Farm(owner, address(agency), address(dyson));
    }
}