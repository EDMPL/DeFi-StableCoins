// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
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
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BURNED_COLLATERAL = 5 ether;


    address public USER = makeAddr("USER");
    address public ADMIN = makeAddr("ADMIN");

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenAddress, uint256 amount);


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

    function testGetAccountCollateralValue() public depositCollateral(USER){
        uint256 expectedTotalCollateralValueInUsd = 2e22; // 10e18 * 2000 = 2e22
        uint256 totalCollateralValueInUsd = engine.getAccountCollateralValue(USER);
        assertEq(expectedTotalCollateralValueInUsd, totalCollateralValueInUsd);
    }


    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral(USER){
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUSD);
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
        // 20000.000000000000000000
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

    function testGetHealthFactorWithNoDebt() public depositCollateral(USER) {
        uint256 healthFactor = engine.getHealthFactor(USER);
        uint256 expectedHealthFactor = type(uint256).max;
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testDscMintZeroAmount() public depositCollateral(USER){
        uint256 healthFactor = engine.getHealthFactor(USER);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(
            DSCEngine.DSCEngine__MustBeMoreThanZero.selector,
            healthFactor
        ));
        engine.mintDsc(0);
    }

    // modifier mintDscToken(uint256 dscAmount) {
    //     bytes32 slot = keccak256(abi.encode(USER, uint256(3))); // https://getfoundry.sh/reference/cheatcodes/store/
    //     vm.store(address(engine), slot, bytes32(uint256(10000)));
    //     _;
    // }

    function testDscMintBadHealthFactor() public depositCollateral(USER){
        // (2e22 * 5e17) / 1e18 = 1e40 / 1e18 = 1e22
        // (1e22 * 1e18) / 1e23 = 1e40 / 1e23 = 1e17
        // 1e17 < 1e18
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector,
            100000000000000000 // 1e17
        ));
        engine.mintDsc(100000);
        vm.stopPrank();
    }

    function testMintDscToken() public depositCollateral(USER){
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        vm.stopPrank();
        assertEq(engine.s_dscMinted(USER), DSC_TO_MINT);
    }

    function testBurnDscZeroAmount() public depositCollateral(USER){
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testMintAndBurnDsc() public depositCollateral(USER){ // this one still error
        // Deposited Collateral 10 ether
        dsc = DecentralizedStableCoin(engine.getDscAddress());
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        dsc.approve(address(engine), DSC_TO_MINT);
        engine.burnDsc(DSC_TO_MINT);
        vm.stopPrank();
        assertEq(engine.s_dscMinted(USER), 0); // 5 - 5
    }

    function testRedeemCollateralIfZero() public depositCollateral(USER){
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralAndCollateralRedeemedEvent() public depositCollateral(USER){
        vm.startPrank(USER);
        vm.expectEmit(true, true, false, true);
        emit CollateralRedeemed(USER, USER, weth, 5 ether);
        engine.redeemCollateral(weth, 5 ether);
        vm.stopPrank();
        uint256 collateralAmount = engine.getCollateralDeposited(USER, weth);
        assertEq(collateralAmount, 5 ether);
    }

    function testRedeemCollateralForDsc() public depositCollateral(USER){
        // Mint Some DSC
        dsc = DecentralizedStableCoin(engine.getDscAddress());
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        //Test
        dsc.approve(address(engine), DSC_TO_MINT);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, DSC_TO_MINT);
        vm.stopPrank();
        assertEq(engine.s_dscMinted(USER), 0);
    }

    function testCannotRedeemMoreCollateralThanDeposited() public depositCollateral(USER) {
        vm.startPrank(USER);
        vm.expectRevert(); // underflow
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1 ether);
        vm.stopPrank();
    }

    function testCannotMintDscIfExceedsCollateralValue() public depositCollateral(USER) {
        vm.startPrank(USER);
        uint256 excessiveMintAmount = 100000; // Exceeds collateral value
        vm.expectRevert(abi.encodeWithSelector(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector,
            1e17 
            // 10 eth = 2e22 collateral in USD
            // (2e22 * 5e17 / 1e18) = 1e40 / 1e18 = 1e22
            // 1e22 * 1e18) / 100000 * 1e18 = 1e40 / 1e23
            // 1e17
        ));
        engine.mintDsc(excessiveMintAmount);
        vm.stopPrank();
    }

    function testHealthFactorDecreasesAfterMintingDsc() public depositCollateral(USER) {
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        uint256 healthFactorAfterMint = engine.getHealthFactor(USER);
        assertLt(healthFactorAfterMint, type(uint256).max); // Health factor should decrease
        vm.stopPrank();
    }

    function testCannotRedeemCollateralIfHealthFactorBreaks() public depositCollateral(USER) {
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        vm.expectRevert(abi.encodeWithSelector(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector,
            0
        ));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testGetAccountInformationAfterMintAndRedeem() public depositCollateral(USER) {
        vm.startPrank(USER);
        engine.mintDsc(DSC_TO_MINT);
        engine.redeemCollateral(weth, BURNED_COLLATERAL);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL - BURNED_COLLATERAL);
        assertEq(totalDscMinted, DSC_TO_MINT);
        assertEq(collateralValueInUSD, expectedCollateralValue);
    }


    function testLiquidateFailsIfHealthFactorIsAboveThreshold() public depositCollateral(USER) {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOK.selector);
        engine.liquidate(weth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // function testLiquidateReducesDebtAndTransfersCollateral() public depositCollateral(USER) {
    //     dsc = DecentralizedStableCoin(engine.getDscAddress());
    //     vm.startPrank(USER);
    //     engine.mintDsc(DSC_TO_MINT);
    //     vm.stopPrank();

    //     // Simulate price drop to make USER liquidatable
    //     vm.mockCall(
    //         ethUsdPriceFeed,
    //         abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
    //         abi.encode(0, 1000e8, 0, 0, 0) // ETH price drops to $1000
    //     );

    //     uint256 initialAdminBalance = ERC20Mock(weth).balanceOf(ADMIN);
    //     uint256 initialUserDebt = engine.s_dscMinted(USER);

    //     vm.startPrank(ADMIN);
    //     dsc.approve(address(engine), DSC_TO_MINT);
    //     engine.liquidate(USER, weth, AMOUNT_COLLATERAL / 2);
    //     vm.stopPrank();

    //     uint256 finalAdminBalance = ERC20Mock(weth).balanceOf(ADMIN);
    //     uint256 finalUserDebt = engine.s_dscMinted(USER);

    //     assertGt(finalAdminBalance, initialAdminBalance); // ADMIN receives collateral
    //     assertLt(finalUserDebt, initialUserDebt); // USER's debt is reduced
    // }

    // function testLiquidateFailsIfNotEnoughDebt() public depositCollateral(USER) {
    //     vm.startPrank(USER);
    //     engine.mintDsc(DSC_TO_MINT);
    //     vm.stopPrank();

    //     // Simulate price drop to make USER liquidatable
    //     vm.mockCall(
    //         ethUsdPriceFeed,
    //         abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
    //         abi.encode(0, 1000e8, 0, 0, 0) // ETH price drops to $1000
    //     );

    //     vm.startPrank(ADMIN);
    //     vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDebtToLiquidate.selector);
    //     engine.liquidate(USER, weth, AMOUNT_COLLATERAL * 2); // Attempt to liquidate more than debt
    //     vm.stopPrank();
    // }

    function testLiquidateFailsIfCollateralAmountIsZero() public depositCollateral(USER) {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testDepositFailsIfCollateralNotApproved() public {
        ERC20Mock testToken = new ERC20Mock("TEST", "TEST", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSC__NotAllowedToken.selector);
        engine.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // function testLiquidateEmitsEvent() public depositCollateral(USER) {
    //     dsc = DecentralizedStableCoin(engine.getDscAddress());
    //     vm.startPrank(USER);
    //     engine.mintDsc(DSC_TO_MINT);
    //     vm.stopPrank();

    //     // Simulate price drop to make USER liquidatable
    //     vm.mockCall(
    //         ethUsdPriceFeed,
    //         abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
    //         abi.encode(0, 1000e8, 0, 0, 0) // ETH price drops to $1000
    //     );

    //     vm.startPrank(ADMIN);
    //     dsc.approve(address(engine), DSC_TO_MINT);
    //     vm.expectEmit(true, true, true, true);
    //     emit CollateralRedeemed(USER, ADMIN, weth, AMOUNT_COLLATERAL / 2);
    //     engine.liquidate(USER, weth, AMOUNT_COLLATERAL / 2);
    //     vm.stopPrank();
    // }

}