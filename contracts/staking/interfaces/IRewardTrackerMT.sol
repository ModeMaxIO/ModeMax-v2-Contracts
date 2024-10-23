// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardTrackerMT {
    function depositBalances(address _account, address _depositToken) external view returns (uint256);
    function stakedAmounts(address _account) external view returns (uint256);
    function updateRewards() external;
    function stake(address _depositToken, uint256 _amount) external;
    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external;
    function unstake(address _depositToken, uint256 _amount) external;
    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external;
    function tokensPerIntervals() external view returns (address[] memory, uint256[] memory);
    function claim(address _receiver) external returns (address[] memory, uint256[] memory);
    function claimForAccount(address _account, address _receiver) external returns (address[] memory, uint256[] memory);
    function claimable(address _account) external view returns (address[] memory, uint256[] memory);
    function averageStakedAmounts(address _account) external view returns (uint256);
    function cumulativeRewards(address _account, address _token) external view returns (uint256);
    function allCumulativeRewards(address _account) external view returns (uint256);
}
