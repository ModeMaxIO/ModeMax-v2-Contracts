// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardDistributorMT {
    function getAllRewardTokens() external view returns (address[] memory);
    function getAllTokensPerIntervals() external view returns (address[] memory, uint256[] memory);
    function zeroTokensPerInterval() external view returns (bool);
    function pendingRewards() external view returns (address[] memory, uint256[] memory);
    function distribute() external returns (address[] memory, uint256[] memory);
}
