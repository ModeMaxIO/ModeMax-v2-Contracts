// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../FeeLog.sol";

interface IFeeLog {
    function gov() external view returns (address);
    function lastFeesAmount() external view returns (uint256);
    function lastTimestamp() external view returns (uint256);
    function isUpdater(address _account) external view returns (bool);
    function setFeesInfo(uint256 _usdAmount, uint256 _timestamp) external;
    function distribute(uint256 _usdAmount, uint256 _timestamp) external;
    function feesInfo() external view returns (uint256, uint256);
}