// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ILiquidityRouter {
    function depositRequestKeysStart() external view returns (uint256);
    function withdrawalRequestKeysStart() external view returns (uint256);
    function depositRequestKeys(uint256 index) external view returns (bytes32);
    function withdrawalRequestKeys(uint256 index) external view returns (bytes32);
    function executeDeposits(uint256 _endIndex, address payable _executionFeeReceiver) external;
    function executeWithdrawals(uint256 _endIndex, address payable _executionFeeReceiver) external;
    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256);
    function setPricesAndExecute(
        int192[] memory _prices,
        uint256 _timestamp,
        uint256 _endIndexForDeposits,
        uint256 _endIndexForWithdrawals,
        uint256 _maxDeposits,
        uint256 _maxWithdrawals
    ) external;

}