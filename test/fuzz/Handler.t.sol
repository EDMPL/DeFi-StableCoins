// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call function

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test{
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timeMintIsCalled;
    uint256 public timeDepositIsCalled;
    uint256 public timeRedeemIsCalled;


    address[] public usersWithCollateral;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc){
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();

        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        timeMintIsCalled = 0;
        timeDepositIsCalled = 0;
        timeRedeemIsCalled = 0;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender);
        // if (engine.getCollateralDeposited(msg.sender, address(collateral)) > 0){
            
        // }
        timeDepositIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        if (usersWithCollateral.length == 0) return;
        address sender = usersWithCollateral[bound(collateralSeed, 0, usersWithCollateral.length - 1)];

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralDeposited(sender, address(collateral));
        if (maxCollateralToRedeem == 0) {
            return;
        }
        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);


        vm.startPrank(sender);
        engine.redeemCollateral(address(collateral), amountCollateral); 
        vm.stopPrank();
        timeRedeemIsCalled++;
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateral.length == 0) return;
        address user = usersWithCollateral[addressSeed % usersWithCollateral.length];

        // uint256 wethDeposited = engine.getCollateralDeposited(user, address(weth));
        // uint256 wbtcDeposited = engine.getCollateralDeposited(user, address(wbtc));
        // if (wethDeposited == 0 && wbtcDeposited == 0) return;

        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(user);
        int256 maxDscToMint = (int256(collateralValueInUSD) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        
        vm.startPrank(user);
        engine.mintDsc(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock){
        if (collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }


}