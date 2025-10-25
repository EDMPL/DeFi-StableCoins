// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        DSCEngine engine;

        if (block.chainid == 31337) {
            // Test/local: deploy directly into the test VM (no broadcast)
            engine = new DSCEngine(tokenAddresses, priceFeedAddresses);
        } else {
            // Script/deploy: use broadcast
            vm.startBroadcast(deployerKey);
            engine = new DSCEngine(tokenAddresses, priceFeedAddresses);
            vm.stopBroadcast();
        }

        return (engine, config);
    }
}
