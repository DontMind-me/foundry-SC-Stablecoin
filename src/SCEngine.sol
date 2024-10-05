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





pragma solidity ^0.8.20;

import {Stablecoin} from "./Stablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title SCEngine
 * @author Ifra Muazzam
 *
 * This system is designed to be as minial as possible, and hae the tokens maintain a 1 token == 1 dollar peg
 *
 * This Stablecoin has the following properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI has no governance, no fees and was only backed by WETH and WBRC
 *
 * Our SC system should always be "overcollaterized". At no point, should the value od all collateral <= dollar backed value of all SC
 *
 * @notice This contract is the core of the SC Sysyem. It handles all the logic for minting and redeeming SC, as well as depositing & withdrawing collateral
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
*/

contract SCEngine is ReentrancyGuard {

    ///////////////
    /// ERRORs ///
    //////////////

    error SCEngine__NeedMoreThanZero();
    error SCEngine__PriceFeedAddressesAndTokenAddressesLengthMustBeSame();
    error SCEngine__NotAllowdToken();
    error SCEngine__TransferFailed();
    error SCEngine__BreaksHealthFactor(uint256 HealthFactor);
    error SCEngine__MintFailed();
    error SCEngine__HealthFactorIsOK();
    error SCEngine__HealthFactorDidNotImprve();

    /////////////
    // TYPES ///
    ////////////

    using OracleLib for AggregatorV3Interface;

    ///////////////////////
    //// STATE VARIALES ///
    ///////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; 
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountSCminted) private s_SCMinted;
    address[] private s_collateralTokens;

    Stablecoin private immutable i_sc;

    /////////////////////
    ////// EVENTS ///////
    /////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    //////////////////
    /// MODIFIERS ///
    /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert SCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert SCEngine__NotAllowdToken();
        }
        _;
    }

    //////////////////
    /// FUNCTIONS ///
    /////////////////

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address scAddress) {
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert SCEngine__PriceFeedAddressesAndTokenAddressesLengthMustBeSame();
        }

        for (uint256 i = 0; i < priceFeedAddresses.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddress[i]);
        }

        i_sc = Stablecoin(scAddress);

    }

    ////////////////////////
    // EXTERNAL FUNCTIONS //
    ////////////////////////

    /*
     *@param tokcollateralAddress: The address of the token to deposit as Collateral
     *@param amountCollateral: The amount of Collateral to deposit
     *@param amountScToMint: The amount of Stablecoin TO Mint
     *@notice This function will deposit your collateral and mint SC in one transaction
     */
    function depositCollateralAndMintSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountScToMint ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintSC(amountScToMint);

    }

    /*
     * @notice Follow CEI (Checks, Effects, Interactions)
     * @param tokcollateralAddress: The address of the token o deposit as Collateral
     * @param amountCollateral: The amount of Collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert SCEngine__TransferFailed();
        }

    }

    /*
     *@param tokcollateralAddress: The address of the token to redeem 
     *@param amountCollateral: The amount of Collateral to redeem
     *@param amountScToBurn: The amount of Stablecoin TO Burn
     *@notice This function will redeem your collateral and burn SC in one transaction
     */

    function redeemCollateralForSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountScToBurn) external {
        burnSC(amountScToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress,amountCollateral,msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice Follows CEI (Checks, Effects, Interactions)
     * @param amountScToMint: The amount of Stablecoin TO Mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintSC(uint256 amountScToMint) public moreThanZero(amountScToMint) nonReentrant() {
        s_SCMinted[msg.sender] += amountScToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_sc.mint(msg.sender, amountScToMint);
        if (!minted) {
            revert SCEngine__MintFailed();
        }


    }

    function burnSC(uint256 amount) public moreThanZero(amount) {
        _burnSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     *@param collateral: The ERC20 collateral address to liquidate from the user
     *@param user: The user who has broken the health factor, Their _healthfactpr should be below MIN_HEALTH_FACTOR
     *@param debtToCover: The amount of SC you want to burn to improve the users Health Factor
     *@notice You can partially liquidate a user
     *@notice You will get a liquidtion bonus for taking the users funds
     *@notice This function working assumes the protocol will be roughly 200% overcollatarellized in order for this to work
     *@notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert SCEngine__HealthFactorIsOK();
        }
        
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalCollateralToRedeem, msg.sender, user);

        _burnSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert SCEngine__HealthFactorDidNotImprve();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    // function getHealthFactor(address user) external view returns(uint256) {
    //     return _healthFactor(user);

    // }

    ////////////////////////////////////
    // INTERNAL AND PRIVATE FUNCTIONS //
    ////////////////////////////////////

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        require(s_collateralDeposited[from][tokenCollateralAddress] >= amountCollateral, "Not enough collateral to redeem");
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert SCEngine__TransferFailed();
        }
    } 

    /*
     * @dev Low-Level internal function, do not call unless the function calling it is checking for healthFactors being broken
     */

    function _burnSC(uint256 amountScToBurn, address onBehalfOf, address scFrom) private {
        s_SCMinted[onBehalfOf] -= amountScToBurn;
        bool success = i_sc.transferFrom(scFrom, address(this), amountScToBurn);
        if(!success) {
            revert SCEngine__TransferFailed();
        }

        i_sc.burn(amountScToBurn);
    }
 


     function _getAccountDetails(address user) private view returns(uint256 totalSCMinted, uint256 CollateralValueInUSD) {
        totalSCMinted = s_SCMinted[user];
        CollateralValueInUSD = getAccountCollateralValue(user);
     }

    /*
     * Returns how close a person is to liquidation
     * If a person goes below 1, they can get liquidated
     */

    function _healthFactor(address user) private view returns(uint256) {

        (uint256 totalSCMinted, uint256 collateralValueInUSD) = _getAccountDetails(user);
        if(totalSCMinted ==0) return type(uint256).max;
        uint256 collateralValueAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD ) / LIQUIDATION_PRECISION;
        uint256 collateralValue = collateralValueAdjustedForThreshold  * PRECISION;
        return (collateralValue) / totalSCMinted;

    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < 1) {
            revert SCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////
    // PUBLIC + EXTERNAL VIEW FUNCTIONS //
    //////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);

    }

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i< s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUsdValue(token, amount);

        }

        return totalCollateralValueInUSD;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInfo(address user) external view returns(uint256 totalScMinted, uint256 CollateralValueInUsd) {
        (totalScMinted, CollateralValueInUsd) = _getAccountDetails(user);
        return (totalScMinted, CollateralValueInUsd);
    }

    ///////////////////////
    // GETTER FUNCIONS //
    /////////////////////

    function getCollateralAmount(address user, address addressToken) view external returns(uint256 collateralAmount) {
        return s_collateralDeposited[user][addressToken];
    }

    function getUserMintedSc(address user) external view returns(uint256) {
        return s_SCMinted[user];
    }

    function getHealthFactor(address user) external view returns(uint256) {
        return _healthFactor(user);
    }

    function getPriceFeed(address token) external view returns(address) {
        return s_priceFeeds[token];
    }

    function getCollateralToken() external view returns(address[] memory) {
        return s_collateralTokens;
    }

    function getSC() external view returns(address) {
        return address(i_sc);
    }

    function getMinHEalthFactor() external pure returns(uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() external pure returns(uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256) {
        return s_collateralDeposited[user][token];
    }
}