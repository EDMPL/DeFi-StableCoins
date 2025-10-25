// SPDX-License-Identifier: MIT

// Have our invariants / properties that holds true
// Our invariants: 
// 1. The total supply of DSC should always be less than total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test{
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (engine, config) = deployer.run();
        require(address(engine) != address(0), "engine not deployed");

        dsc = DecentralizedStableCoin(engine.getDscAddress());
        require(address(dsc) != address(0), "dsc not deployed");
        
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(engine));
    }

    function openInvariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("Total Supply: ", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}