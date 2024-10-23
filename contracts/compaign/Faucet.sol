// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import {IFaucet} from "./interfaces/IFaucet.sol";
import "../tokens/FaucetToken.sol";
import "../libraries/utils/ReentrancyGuard.sol";

    struct TokenConfig {
        address tokenContract;
        string name;
        string symbol;
        uint256 decimals;
        uint256 capAmount;
    }

contract Faucet is ReentrancyGuard, IFaucet {

    address public override gov;
    uint256 public override accountAmount;
    TokenConfig[] public claimedTokens;
    mapping (address => uint256) public override maxAmounts;
    mapping (address => bool) public override claimedAccounts;
    mapping (address => mapping (address => uint256)) public override claimedAmounts;

    constructor() public {
        gov = msg.sender;
    }

    function setGov(address _gov) external {
        _onlyGov();
        gov = _gov;
    }

    function setTokenConfig(TokenConfig memory _tokenConfig) external override {
        _onlyGov();
        maxAmounts[_tokenConfig.tokenContract] = _tokenConfig.capAmount;
        claimedTokens.push(_tokenConfig);
    }

    function mint(address _token, address _account, uint256 _amount) public override nonReentrant returns (uint256) {
        _onlyGov();
        FaucetToken(_token).mint(_account, _amount);
        return _amount;
    }

    function enableFaucet(address _token) public {
        _onlyGov();
        FaucetToken(_token).enableFaucet();
    }

    function disableFaucet(address _token) public {
        _onlyGov();
        FaucetToken(_token).disableFaucet();
    }

    function setDropletAmount(address _token, uint256 _dropletAmount) public {
        _onlyGov();
        FaucetToken(_token).setDropletAmount(_dropletAmount);
    }

    function upgradeVault(address _newVault, address _token, uint256 _amount) external {
        _onlyGov();
        IERC20(_token).transfer(_newVault, _amount);
    }

    function claim(address _token, uint256 _amount) external override nonReentrant returns (uint256) {
        uint256 _canAmount = maxAmounts[_token] - claimedAmounts[msg.sender][_token];
        require(_canAmount >= _amount, "Faucet: insufficient amount");
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "Faucet: Insufficient inventory");
        claimedAmounts[msg.sender][_token] = claimedAmounts[msg.sender][_token] + _amount;
        require(IERC20(_token).transfer(msg.sender, _amount), "Faucet: transfer failure");
        if (!claimedAccounts[msg.sender]) {
            claimedAccounts[msg.sender] = true;
            accountAmount ++;
        }
        return _amount;
    }

    function claimFaucetToken(address _token, uint256 _amount) external override nonReentrant returns (uint256) {
        uint256 _canAmount = maxAmounts[_token] - claimedAmounts[msg.sender][_token];
        require(_canAmount >= _amount, "Faucet: insufficient amount");
        claimedAmounts[msg.sender][_token] = claimedAmounts[msg.sender][_token] + _amount;
        FaucetToken(_token).mint(msg.sender, _amount);
        if (!claimedAccounts[msg.sender]) {
            claimedAccounts[msg.sender] = true;
            accountAmount ++;
        }
        return _amount;
    }

    function claimedTokenAmount(address _token) external override view returns (uint256) {
        return claimedAmounts[msg.sender][_token];
    }

    function claimedTokenAmounts(address[] memory _tokens) external override view returns (uint256[] memory) {
        uint256[] memory _claimedAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _claimedAmounts[i] = claimedAmounts[msg.sender][_tokens[i]];
        }
        return _claimedAmounts;
    }

    function tokenLength() external override view returns (uint256) {
        return claimedTokens.length;
    }

    function tokenList() external override view returns (TokenConfig[] memory) {
//        TokenConfig[] memory _claimTokenConfigs = new TokenConfig[](claimedTokens.length);
//        for (uint256 i = 0; i < claimedTokens.length; i++) {
////            TokenConfig memory _tokenConfig = claimedTokens[i];
//            _claimTokenConfigs[i] = claimedTokens[i];
//        }
//        return _claimTokenConfigs;

        return claimedTokens;
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _onlyGov() private view {
        require(msg.sender == gov, "Faucet: forbidden");
    }

}