//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeploySC} from "../../script/DeploySC.s.sol";
import {SCEngine} from "../../src/SCEngine.sol";
import {Stablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";

contract SCEngineTest is Test {
    DeploySC deployer;
    Stablecoin sc;
    SCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;

    address[] public tokenAddresses;
    address[] public feedAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MINTED_SC = 1 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    MockV3Aggregator liquidationEthPriceFeed = new MockV3Aggregator(0, 1000e8);

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    function setUp() public {

        deployer = new DeploySC();
        (sc, engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed , weth, ,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        
    }

    ////////////////////////
    // CONSTRUCTOR TESTS //
    ///////////////////////
    address[] public priceFeedsAddresses;

    function testRevertsIfTokenLengthNotEqualToPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);
        
        vm.expectRevert(SCEngine.SCEngine__PriceFeedAddressesAndTokenAddressesLengthMustBeSame.selector);

        new SCEngine(tokenAddresses, priceFeedsAddresses, address(sc));
    }

    //////////////////
    // PRICE TESTS //
    /////////////////


    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(actualWeth, expectedWeth);
    }

        /////////////////////////
        // DEPOSIT COLLATERAL //
        ////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), 10 ether);

        vm.expectRevert(SCEngine.SCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertswithUnApprovedColalteral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.prank(USER);
        vm.expectRevert(SCEngine.SCEngine__NotAllowdToken.selector);
        engine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
    }

  

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral() {

        (uint256 totalScMinted, uint256 CollateralValueInUsd) = engine.getAccountInfo(USER);

        uint256 expectedScMinted = 0;
        uint256 expectedDepositedCollateral = engine.getTokenAmountFromUsd(weth, CollateralValueInUsd);

        assertEq(expectedScMinted, totalScMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositedCollateral);
    }

    function testCollateralDepositedEventsGetsemitetd() public  {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectEmit(true, true, false, true, address(engine));
        emit CollateralDeposited(USER, address(weth), COLLATERAL_AMOUNT);
        engine.depositCollateral(address(weth), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCollateralGetsDepositedToEngine() public depositedCollateral {
        uint256 userCollateral = engine.getCollateralAmount(USER, address(weth));
        uint256 engineWethBalance = ERC20Mock(weth).balanceOf(address(engine));
        assertEq(userCollateral, COLLATERAL_AMOUNT);
        assertEq(engineWethBalance, COLLATERAL_AMOUNT);
    }

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockSc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockSc)];
        feedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        SCEngine mockEngine = new SCEngine(tokenAddresses, feedAddresses, address(mockSc));
        mockSc.mint(USER, COLLATERAL_AMOUNT);

        vm.prank(owner);
        mockSc.transferOwnership(address(mockEngine));
        vm.startPrank(USER);
        ERC20Mock(address(mockSc)).approve(address(mockEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(SCEngine.SCEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockSc), COLLATERAL_AMOUNT);
        vm.stopPrank();


    }

        /////////////////////
        ////// MINT SC //////
        /////////////////////

    modifier mintedSc() {
        vm.startPrank(USER);
        ERC20Mock(address(sc)).approve(address(engine), COLLATERAL_AMOUNT);
        engine.mintSC(2 ether);
        vm.stopPrank();
        _;
    }

    function testRevertIfMintedScIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(SCEngine.SCEngine__NeedMoreThanZero.selector);
        engine.mintSC(0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(SCEngine.SCEngine__BreaksHealthFactor.selector, 0));
        engine.mintSC(1);
        vm.stopPrank();
    }

    function testUserGetsAddedToMapping() public depositedCollateral {
        vm.prank(USER);
        engine.mintSC(1 ether);
        assertEq(engine.getUserMintedSc(USER), 1e18);
        
    }

    function testSuccessfulMinting() public depositedCollateral {
        uint256 amountToMint = 10;
        vm.prank(USER);
        engine.mintSC(amountToMint);
        uint256 mintedSC = ERC20Mock(address(sc)).balanceOf(USER);
        assertEq(mintedSC, amountToMint);
    }

    function testMintFailure() public depositedCollateral {
        vm.startPrank(USER);
    
        vm.mockCall(
            address(sc),
            abi.encodeWithSignature("mint(address,uint256)", USER, 1),
            abi.encode(false)
        );
        vm.expectRevert(SCEngine.SCEngine__MintFailed.selector);
        engine.mintSC(1);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        SCEngine mockEngine = new SCEngine(tokenAddresses, feedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(SCEngine.SCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintSC(weth, COLLATERAL_AMOUNT, MINTED_SC);
        vm.stopPrank();
    }
        
    //////////////
    // BURN SC //
    /////////////


    function testMintedScAmountDecreasesInMapping() public depositedCollateral mintedSc {
        vm.prank(USER);
        engine.burnSC(MINTED_SC);
        assertEq(1e18, engine.getUserMintedSc(USER));
    }



    ///////////////////////
    // REDEEM COLLATERAL //
    ///////////////////////

    modifier burnSC() {
        vm.startPrank(USER);
        //ERC20Mock(address(sc)).approve(address(engine), COLLATERAL_AMOUNT);
        engine.burnSC(1);
        vm.stopPrank();
        _;
    }

    function testCollateralAmountDecresesinMapping() public depositedCollateral mintedSc burnSC {
        uint256 collateralAmountBeforeRedeem = engine.getCollateralAmount(USER, address(weth));
        vm.prank(USER);
        engine.redeemCollateral(address(weth), 3 ether);
        uint256 collateralAmountAfterRedeem = engine.getCollateralAmount(USER, address(weth));

        assertEq((collateralAmountBeforeRedeem - 3 ether), collateralAmountAfterRedeem);
    }

    function testCantRedeemIfHealthFactorBreaks() public depositedCollateral mintedSc burnSC {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(SCEngine.SCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(address(weth), 10 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralEventGetsEmitted() public depositedCollateral mintedSc burnSC {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, address(weth), 3 ether);
        vm.startPrank(USER);
        engine.redeemCollateral(address(weth), 3 ether);

        vm.stopPrank();
    }

    function testRedeemCollateralTransfersMoneyToUser() public depositedCollateral mintedSc burnSC {
        vm.startPrank(USER);
        engine.redeemCollateral(address(weth), 5 ether);
        uint256 collateralBalance = ERC20Mock(address(weth)).balanceOf(USER);
        assertEq(collateralBalance, 5 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsIfHealthFactorBroken() public depositedCollateral mintedSc {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(SCEngine.SCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(address(weth), 10 ether);
        vm.stopPrank();
    }

    ////////////////////
    // HEALTH FACTOR //
    ///////////////////

     function testProperlyReportsHealthFactor() public depositedCollateral mintedSc {
        uint256 expectedHealthFactor = 5000 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, healthFactor);

        //2500000000000000000
        //5000000000000000000000000000000000000000

     }

    
    //////////////////
    // LIQUIDATION //
    /////////////////

    modifier liquidatorBalance() {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        ERC20Mock(address(sc)).approve(address(engine), COLLATERAL_AMOUNT);
        engine.mintSC(4);
        vm.stopPrank();
        _;
    }

    modifier badUser() {
        _;
    }

    function testLiquidationMorethanZero() public depositedCollateral mintedSc {
        vm.startPrank(USER);
        vm.expectRevert(SCEngine.SCEngine__NeedMoreThanZero.selector);
        engine.liquidate(address(weth), LIQUIDATOR, 0);
        vm.stopPrank();
    }

    function testCantLiquidateUserIfHealthFactorOK() public depositedCollateral mintedSc liquidatorBalance {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(SCEngine.SCEngine__HealthFactorIsOK.selector);
        engine.liquidate(address(weth), USER, 1);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // View & Pure Function Tests   //
    //////////////////////////////////

    function testgetPriceFeedOfToken() public {
        address priceFeed = engine.getPriceFeed(weth);
        assertEq(ethUsdPriceFeed, priceFeed);
    }

    function testgetUserCollateral() public depositedCollateral {
        uint256 expectedCollateral = 10 ether;
        uint256 collateral = engine.getCollateralAmount(USER, weth);
        assertEq(expectedCollateral, collateral);
    }

    function testgetCollateralTokens() public {
        address[] memory collateralToken = engine.getCollateralToken();
        assertEq(collateralToken[0], weth);
    }

    function testgetSCAddress() public {
        address expectedSc = engine.getSC();
        assertEq(address(sc), expectedSc);

    }

    function testGetMinHealthFactor() public {
        uint256 expectedMinHEalthFactor = engine.getMinHEalthFactor();
        assertEq(MIN_HEALTH_FACTOR, expectedMinHEalthFactor);
    }

    function testGetLiquidationThreshold() public {
        uint256 expectedLiquidationThreshold = engine.getLiquidationThreshold();
        assertEq(LIQUIDATION_THRESHOLD, expectedLiquidationThreshold);
    }

    function testgetAccountCollateralValuefromInfo() public depositedCollateral {
        (, uint256 collateralValueinUsd) = engine.getAccountInfo(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(collateralValueinUsd, expectedCollateralValue);
    }

    function testgetCollateralBalanceofUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        uint256 expectedCollateralAmount = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(expectedCollateralAmount, COLLATERAL_AMOUNT);
    }

    function testgetAccountCollateralVAlue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(collateralValue, expectedCollateralValue);
    }






    




}