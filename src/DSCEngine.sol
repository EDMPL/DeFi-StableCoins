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

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant FEE_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;


    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);

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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
     * @notice Follows CEI
     * @param amountDscToMint The amomunt of DSC to be minted
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSC__MintedFailed();
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUSD) {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
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
        return(collateralAdjustedForPrecision * FEE_PRECISION) / totalDscMinted;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

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