// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../ReferralDistributor.sol";

interface IReferralDistributor {
    function gov() external view returns (address);
    function isHandler(address _account) external view returns (bool);
    function claimableDiscounts(address _account, address _token) external view returns (uint256);
    function claimedDiscounts(address _account, address _token) external view returns (uint256);
    function claimableRebates(address _account, address _token) external view returns (uint256);
    function claimedRebates(address _account, address _token) external view returns (uint256);
    function reserveAmounts(address _token) external view returns (uint256);
    function getAllRewardTokens() external view returns (address[] memory);
    function affiliateClaimable() external view returns (address[] memory, uint256[] memory);
    function affiliateClaimableForAccount(address _account) external view returns (address[] memory, uint256[] memory);
    function traderClaimable() external view returns (address[] memory, uint256[] memory);
    function traderClaimableForAccount(address _account) external view returns (address[] memory, uint256[] memory);
}

