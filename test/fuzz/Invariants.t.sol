//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeploySC} from "../../script/DeploySC.s.sol";
import {SCEngine} from "../../src/SCEngine.sol";
import {Stablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeploySC deployer;
    SCEngine engine;
    Stablecoin sc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeploySC();
        (sc, engine, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(engine, sc);
        targetContract(address(handler));
        //targetContract(address(engine));

    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = sc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalBtcDeposited= IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(weth, totalBtcDeposited);

        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("totalSupply Value:", totalSupply);
        console.log("Times mint Is called", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}