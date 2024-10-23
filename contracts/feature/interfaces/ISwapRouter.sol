// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ISwapRouter {
    function swapRequestKeysStart() external view returns (uint256);
    function swapRequestKeys(uint256 index) external view returns (bytes32);
    function getRequestQueueLengths() external view returns (uint256, uint256);
    function executeSwaps(uint256 _endIndex, address payable _executionFeeReceiver) external;
    function setPricesAndExecute(
        int192[] memory _prices,
        uint256 _timestamp,
        uint256 _endIndexForSwaps,
        uint256 _maxSwaps
    ) external;
}