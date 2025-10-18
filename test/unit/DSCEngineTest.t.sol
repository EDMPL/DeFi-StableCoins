// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;


    address public USER = makeAddr("USER");

    function setUp() public {
        deployer = new DeployDSC();
        (engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }


    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressLengthMustBeTheSame.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses);

    }

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; // 15e18 * 2000/ETH = 30,000e18
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

}