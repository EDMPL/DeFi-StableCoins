// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";



/*
 * @title DecentralizedStableCoin
 * @author Jeremia Geraldi
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged / Anchored to USD
 *
 * This contract is meant to be governed by DSCEngine.
 * It implements the ERC20 logic for the decentralized stablecoin system.
 * 
 * @notice This contract is using AccessControl module from OpenZeppelin for Authorization Check.
 */

contract DecentralizedStableCoin is ERC20Burnable, AccessControl {

    // ====== Custom Errors ======
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BalanceLessThanAmountBurned();
    error DecentralizedStableCoin__NotZeroAddress();

    // ====== Role Definitions ======
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");


    // ====== Constructor ======
    constructor(address admin) ERC20("Decentralized Stable Coins", "DSC") {
        // The deployer (admin) gets admin role with the rights to mint and burn token
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
    }

    // This function is used for testing purpose.
    // function grantAdminRole(address user) external onlyEngine onlyRole(DEFAULT_ADMIN_ROLE){
    //     _grantRole(DEFAULT_ADMIN_ROLE, user);
    // }

    // ====== External Mint Function ======
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) returns (bool) {
        if (_to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (_amount == 0) revert DecentralizedStableCoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }

    // ====== External Burn Function ======
    // Allow only addresses with the BURNER_ROLE to burn tokens from arbitrary accounts
    function burnFromAddress(address _from, uint256 _amount) external onlyRole(BURNER_ROLE) {
        if (_from == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (_amount == 0) revert DecentralizedStableCoin__MustBeMoreThanZero();

        uint256 balance = balanceOf(_from);
        if (balance < _amount) revert DecentralizedStableCoin__BalanceLessThanAmountBurned();

        _burn(_from, _amount);
    }

    // Optional: Normal user self-burn is still allowed through ERC20Burnable.burn()
    // Users can call `burn(amount)` directly on their own tokens
}
