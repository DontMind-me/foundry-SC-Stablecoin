//SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SCEngine} from "./SCEngine.sol";

/** 
 * @title Stablecoin
 * @author Ifra Muazzam 
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stabliity: Pegged to USD
 *
 * This Contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our Stablecoin system.
 *
 */

contract Stablecoin is ERC20Burnable, Ownable {

    error Stablecoin__MustBeMoreThanZero();
    error Sablecoin__BurnAmountExceedsBalance();
    error Stablecoin__NotZeroAddress();

    constructor() ERC20("Stablecoin", "SC") Ownable(msg.sender) {}


    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount == 0) {
            revert Stablecoin__MustBeMoreThanZero();
        }

        if (_amount > balance) {
            revert Sablecoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if (_to == address(0)) {
            revert Stablecoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert Stablecoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }

}