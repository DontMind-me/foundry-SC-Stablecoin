//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Stablecoin} from "../src/Stablecoin.sol";
import {SCEngine} from "../src/SCEngine.sol";
import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddresses;

    function run() external returns(Stablecoin, SCEngine, HelperConfig) {
        HelperConfig config =  new HelperConfig();
        (address wethUsdPriceFeed,
        address wbtcUsdPriceFeed,
        address weth,
        address wbtc,
        uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        Stablecoin sc = new Stablecoin();
        SCEngine engine = new SCEngine(tokenAddress, priceFeedAddresses, address(sc));
        console.log("Ownership Transfer",address(engine));
        sc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (sc, engine, config);
    }
        

}