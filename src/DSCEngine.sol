// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Jeremia Geraldi (Inspired by Patrick Collins and his course)
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1
 * token == $1 peg.
 * The stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmic Stable
 *
 * Our DSC system should always be "overcollaterized". The value of all collateral should always be greater than the $
 * backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC,
 * as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 *
 */

contract DSCEngine is ReentrancyGuard{
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMustBeTheSame();
    error DSC__NotAllowedToken();
    error DSC__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSC__MintedFailed();
    error DSCEngine__HealthFactorIsOK();
    error DSCEngine__HealthFactorNotImproved();

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant FEE_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;


    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenAddress, uint256 amount);

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses
    ){
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMustBeTheSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = new DecentralizedStableCoin(address(this));

    }

    modifier isAllowedToken(address token){
        if (s_priceFeeds[token] == address(0)) revert DSC__NotAllowedToken();
        _;
    }

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amomunt of DSC to be minted
     * @notice this function will deposit user collateral and mint Dsc in one function
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSC__TransferFailed();
    }

    /*
     * @param tokenCollateralAddress The address of the token to redeem 
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of coin to burn
     * @notice This function burn the DSC and redeem the collateral in one transaction.
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral has check for health factor
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        // Newer Solidity Compiler Do Check if the Current Balance is not Lesser than ammountCollateral (SafeaMath)
        // Example: 100 - 1000 will throws an error
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice Follows CEI
     * @param amountDscToMint The amount of DSC to be minted
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSC__MintedFailed();
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // This probably is not needed since burning the coin will not worsened the healthfactor
    }

    // If we do start nearing undercollaterization, we need someone to liquidate positions
    // If someone is almost undercollaterized, we will pay you to liquidate them

    /*
     * @param collateral The ERC20 collateral address to liquidate them from the user
     * @param user The user that broke the health factor
     * @param debtToCover The amount of DSC to burn to improve the users health factor
     * @notice Liquidator can partially liquidate a user.
     * @notice Liquidator will get a liquidation bonus for taking the user funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollaterized.
     * @notice This will not work if the protocol 100% collaterized or undercollaterized.
    */

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsOK();
        // Burn the user DSC debt
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Give 10% Bonus to the Liquidator
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) revert DSCEngine__HealthFactorNotImproved();
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external {}

    /*
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
    */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This condition might not be reached when error occured
        if (!success) {
            revert DSC__TransferFailed();  
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSC__TransferFailed();
        }
    }

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUSD) {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return(totalDscMinted, collateralValueInUSD);
    }

    /*
     * Returns how close to liquidation user is
     * If a user goes below 1, then they can get liquidated
     */
    // ($100 x 50) / 100  = 50
    // 50 * 1e18 / 100
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForPrecision = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return((collateralAdjustedForPrecision * FEE_PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((usdAmountInWei * FEE_PRECISION) / (uint256(price) * ADDITIONAL_FEE_PRECISION));
    }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd){
        for (uint256 i = 0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // The returned value from chainlink will be 1e8 for ETH and BTC
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * amount) / FEE_PRECISION;
    }
}