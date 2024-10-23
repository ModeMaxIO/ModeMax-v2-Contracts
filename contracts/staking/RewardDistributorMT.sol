// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributorMT.sol";
import "./interfaces/IRewardTracker.sol";
import "../access/Governable.sol";

contract RewardDistributorMT is IRewardDistributorMT, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address[] public rewardTokens;
    mapping(address => uint256) public tokensPerIntervals;
    uint256 public lastDistributionTime;
    address public rewardTracker;

    address public admin;

    event Distribute(address[] tokens, uint256[] amounts);
    event TokensPerIntervalChange(address[] tokens, uint256[] amounts);

    modifier onlyAdmin() {
        require(msg.sender == admin, "RewardDistributor: forbidden");
        _;
    }

    constructor(address[] memory _rewardTokens, address _rewardTracker) public {
        rewardTokens = _rewardTokens;
        rewardTracker = _rewardTracker;
        admin = msg.sender;
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
    }

    function setRewardTokens(address[] memory _rewardTokens) external onlyAdmin {
        rewardTokens = _rewardTokens;
    }

    function addRewardToken(address _rewardToken) external onlyAdmin {
        rewardTokens.push(_rewardToken);
    }

    function updateRewardToken(uint256 _index, address _newAddress) external onlyAdmin {
        require(_index < rewardTokens.length, "Index out of bounds");
        rewardTokens[_index] = _newAddress;
    }

    function removeRewardToken(uint256 _index) external onlyAdmin {
        require(_index < rewardTokens.length, "Index out of bounds");
        rewardTokens[_index] = rewardTokens[rewardTokens.length - 1];
        rewardTokens.pop();
    }

    function getAllRewardTokens() external view override returns (address[] memory) {
        return rewardTokens;
    }

    function getAllTokensPerIntervals() external view override returns (address[] memory, uint256[] memory) {
        address [] memory _tokens = new address[](rewardTokens.length);
        uint256[] memory _amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            _tokens[i] = rewardTokens[i];
            _amounts[i] = tokensPerIntervals[rewardTokens[i]];
        }
        return (_tokens, _amounts);
    }

    function zeroTokensPerInterval() external view override returns (bool) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (tokensPerIntervals[rewardTokens[i]] > 0) {
                return false;
            }
        }
        return true;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function updateLastDistributionTime() external onlyAdmin {
        lastDistributionTime = block.timestamp;
    }

    function setTokensPerIntervals(address[] memory _tokens, uint256[] memory _amounts) external onlyAdmin {
        require(lastDistributionTime != 0, "RewardDistributor: invalid lastDistributionTime");
        IRewardTracker(rewardTracker).updateRewards();
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokensPerIntervals[_tokens[i]] = _amounts[i];
        }
        emit TokensPerIntervalChange(_tokens, _amounts);
    }

    function pendingRewards() public view override returns (address[] memory, uint256[] memory) {
        uint256 timeDiff = block.timestamp.sub(lastDistributionTime);

        address[] memory _tokens = new address[](rewardTokens.length);
        uint256[] memory _amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address _token = rewardTokens[i];
            _tokens[i] = _token;
            uint256 _amount = tokensPerIntervals[_token].mul(timeDiff);
            uint256 _balance = IERC20(_token).balanceOf(address(this));
            if (_amount > _balance) { _amount = _balance; }
            _amounts[i] = _amount;
        }

        return (_tokens, _amounts);
    }

    function distribute() external override returns (address[] memory, uint256[] memory) {
        require(msg.sender == rewardTracker, "RewardDistributor: invalid msg.sender");
        (address[] memory _tokens, uint256[] memory _amounts) = pendingRewards();

        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _amount = _amounts[i];
            if (_amount > 0) {
                address _token = _tokens[i];
                lastDistributionTime = block.timestamp;
                uint256 _balance = IERC20(_token).balanceOf(address(this));
                if (_amount > _balance) { _amount = _balance; }
                IERC20(_token).safeTransfer(msg.sender, _amount);
            }
            _amounts[i] = _amount;
        }

        emit Distribute(_tokens, _amounts);
        return (_tokens, _amounts);
    }
}
