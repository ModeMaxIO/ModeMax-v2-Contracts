// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../Faucet.sol";

interface IFaucet {
    function gov() external view returns (address);
    function accountAmount() external view returns (uint256);
    function maxAmounts(address _token) external view returns (uint256);
    function claimedAccounts(address _account) external view returns (bool);
    function claimedAmounts(address _account, address _token) external view returns (uint256);
    function setTokenConfig(TokenConfig memory _tokenConfig) external;
    function claim(address _token, uint256 _amount) external returns (uint256);
    function claimFaucetToken(address _token, uint256 _amount) external returns (uint256);
    function tokenLength() external view returns (uint256);
    function tokenList() external view returns (TokenConfig[] memory);
    function claimedTokenAmount(address _token) external view returns (uint256);
    function claimedTokenAmounts(address[] memory _tokens) external view returns (uint256[] memory);

    function mint(address _token, address _account, uint256 _amount) external returns (uint256);
}