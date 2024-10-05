//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

/*
 *@title OracleLib
 *@author Ifra Muazzam
 *@notice This Library is used to check the Chainlink Oracle for state data.
 * If a price is stale, the function will revert and render the DSCEngine unusable - this is by design
 * We want the DSCEngine to freeze if prices become stale
 * 
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol... too bad
 */

library OracleLib {
    error OracleLib__StatePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StatePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}