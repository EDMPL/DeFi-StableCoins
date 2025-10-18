// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address private constant ADMIN_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    function run() external returns(DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses);
        // DecentralizedStableCoin dsc = new DecentralizedStableCoin(ADDRESS);
        vm.stopBroadcast();
        return(dscEngine, config);
    }
}