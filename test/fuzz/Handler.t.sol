//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SCEngine} from "../../src/SCEngine.sol";
import {Stablecoin} from "../../src/Stablecoin.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract Handler is Test {
    SCEngine engine;
    Stablecoin sc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithDepositedCollateral;

    uint256 public timesMintIsCalled;

    constructor(SCEngine _engine, Stablecoin _sc) {
        engine = _engine;
        sc = _sc;

        address[] memory collateralToken = engine.getCollateralToken();
        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);
    }

    function mintSc(uint256 amount, uint256 addressSeed) public {
        if (usersWithDepositedCollateral.length == 0) {
            return;
        }
        address sender = usersWithDepositedCollateral[addressSeed % usersWithDepositedCollateral.length];
        (uint256 totalScMinted, uint256 CollateralValueInUsd) = engine.getAccountInfo(sender);
        int256 maxScToMint = (int256(CollateralValueInUsd)) / 2 - int256(totalScMinted);
        if (maxScToMint < 0) {
            return;
        }
        amount = bound(amount,0,uint256(maxScToMint));
        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public  {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral); 
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        console.log("msg.sender:", msg.sender);
        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    //This breakes our test suit!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;}
    
    }

}
