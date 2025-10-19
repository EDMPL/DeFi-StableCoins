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
    uint256 public constant DSC_TO_MINT = 5;


    address public USER = makeAddr("USER");
    address public ADMIN = makeAddr("ADMIN");

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);


    function setUp() public {
        deployer = new DeployDSC();
        (engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(ADMIN, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(address(engine), STARTING_ERC20_BALANCE);
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

    function testGetTokenAmountFromUsd() public view{
        uint256 usdAmount = 100 ether;
        // wEth price: 2000 -> 100 / 2000 = 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock testToken = new ERC20Mock("TEST", "TEST", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSC__NotAllowedToken.selector);
        engine.depositCollateral(address(testToken), STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }

    modifier depositCollateral(address role) {
        vm.startPrank(role);
        ERC20Mock(weth).approve(address(engine), STARTING_ERC20_BALANCE);
        engine.depositCollateral(weth, STARTING_ERC20_BALANCE);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral(USER){
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUSD);
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testMintDscIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDsc(0);
    }

    function testMintDscAuthorizationCheck() public depositCollateral(USER){
        vm.expectRevert();
        engine.mintDsc(DSC_TO_MINT);
    }

    function testMintDscAccountBalance() public depositCollateral(address(engine)){
        vm.startPrank(address(engine));
        engine.mintDsc(DSC_TO_MINT);
        uint256 currentDscBalance = engine.s_dscMinted(address(engine));
        vm.stopPrank();
        assertEq(DSC_TO_MINT, currentDscBalance);
    }

}