// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// @title IAdapterPyth.sol
// @dev Interface for a oracle adapter
interface IAdapterPyth {
    function latestPrice(bytes32 priceFeedId, uint8 decimals) external view returns (
        int256 price,
        uint256 timestamp
    );
}