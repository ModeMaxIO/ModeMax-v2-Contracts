// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/token/IERC20.sol";
import "../libraries/math/SafeMath.sol";
import "../libraries/token/SafeERC20.sol";
import "./interfaces/IReferralDistributor.sol";
import "../libraries/utils/ReentrancyGuard.sol";

contract ReferralDistributor is ReentrancyGuard, IReferralDistributor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint public constant affiliateRewardsTypeId = 1;
    uint public constant traderDiscountsTypeId = 2;

    address public override gov;
    bool public inPrivateClaimingMode;

    address[] public rewardTokens;
    mapping (address => bool) public override isHandler;
    mapping (address => mapping (address => uint256)) public override claimableDiscounts;
    mapping (address => mapping (address => uint256)) public override claimedDiscounts;
    mapping (address => mapping (address => uint256)) public override claimableRebates;
    mapping (address => mapping (address => uint256)) public override claimedRebates;
    mapping (address => uint256) public override reserveAmounts;

    event SetGov(address account);
    event ClaimRewards(uint256 indexed typeId, address indexed account, address[] tokens, uint256[] amounts);
    event DistributeRewards(uint256 indexed typeId, address indexed account, address[] tokens, uint256[] amounts);
    event DepositTokens(address indexed from, address[] tokens, uint256[] amounts);
    event DistributePrices(address[] tokens, uint128[] prices);

    constructor() public {
        gov = msg.sender;
    }

    function setGov(address _gov) external {
        _onlyGov();
        require(_gov != address(0), "invalid address");
        gov = _gov;
        emit SetGov(_gov);
    }

    function setHandler(address _account, bool _isActive) external {
        _onlyGov();
        isHandler[_account] = _isActive;
    }

    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external {
        _onlyGov();
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    function setRewardTokens(address[] memory _rewardTokens) external {
        _onlyGov();
        rewardTokens = _rewardTokens;
    }

    function addRewardToken(address _rewardToken) external {
        _onlyGov();
        rewardTokens.push(_rewardToken);
    }

    function updateRewardToken(uint256 _index, address _newAddress) external {
        _onlyGov();
        require(_index < rewardTokens.length, "Index out of bounds");
        rewardTokens[_index] = _newAddress;
    }

    function removeRewardToken(uint256 _index) external {
        _onlyGov();
        require(_index < rewardTokens.length, "Index out of bounds");
        rewardTokens[_index] = rewardTokens[rewardTokens.length - 1];
        rewardTokens.pop();
    }

    function getAllRewardTokens() external view override returns (address[] memory) {
        return rewardTokens;
    }

    function affiliateClaimable() external view override returns (address[] memory, uint256[] memory) {
        return _claimable(msg.sender, affiliateRewardsTypeId);
    }

    function affiliateClaimableForAccount(address _account) external view override returns (address[] memory, uint256[] memory) {
        return _claimable(_account, affiliateRewardsTypeId);
    }

    function traderClaimable() external view override returns (address[] memory, uint256[] memory) {
        return _claimable(msg.sender, traderDiscountsTypeId);
    }

    function traderClaimableForAccount(address _account) external view override returns (address[] memory, uint256[] memory) {
        return _claimable(_account, traderDiscountsTypeId);
    }

    function affiliateClaim() external nonReentrant returns (address[] memory, uint256[] memory) {
        if (inPrivateClaimingMode) { revert("action not enabled"); }
        return _claim(msg.sender, affiliateRewardsTypeId);
    }

    function traderClaim() external nonReentrant returns (address[] memory, uint256[] memory) {
        if (inPrivateClaimingMode) { revert("action not enabled"); }
        return _claim(msg.sender, traderDiscountsTypeId);
    }

    function emitPrices(address[] memory _tokens, uint128[] memory _prices) external {
        _onlyHandler();
        emit DistributePrices(_tokens, _prices);
    }

    function affiliateDistribute(
        address[] memory _recipients,
        address[] memory _tokens,
        uint256[][] memory _amounts
    ) external {
        _onlyHandler();
        _distribute(affiliateRewardsTypeId, _recipients, _tokens, _amounts);
    }

    function traderDistribute(
        address[] memory _recipients,
        address[] memory _tokens,
        uint256[][] memory _amounts
    ) external {
        _onlyHandler();
        _distribute(traderDiscountsTypeId, _recipients, _tokens, _amounts);
    }

    function _distribute(
        uint256 _typeId,
        address[] memory _recipients,
        address[] memory _tokens,
        uint256[][] memory _amounts
    ) internal {
        require(_recipients.length == _amounts.length, "Invalid input: recipients and amounts length mismatch");
        require(_tokens.length > 0, "No tokens provided");
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i].length == _tokens.length, "Invalid input: tokens and amounts length mismatch");
        }

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            uint256[] memory _accountAmounts = new uint256[](_tokens.length);

            for (uint256 j = 0; j < _tokens.length; j++) {
                address token = _tokens[j];
                uint256 amount = _amounts[i][j];
                _accountAmounts[j] = amount;
                if (amount > 0) {
                    reserveAmounts[token] = reserveAmounts[token].add(amount);
                    if (_typeId == affiliateRewardsTypeId) {
                        claimableRebates[recipient][token] = claimableRebates[recipient][token].add(amount);
                    } else if (_typeId == traderDiscountsTypeId) {
                        claimableDiscounts[recipient][token] = claimableDiscounts[recipient][token].add(amount);
                    }
                }
            }
            emit DistributeRewards(_typeId, recipient, _tokens, _accountAmounts);
        }
    }

    function _claim(address _account, uint256 _typeId) internal returns (address[] memory, uint256[] memory) {
        address[] memory _tokens = new address[](rewardTokens.length);
        uint256[] memory _amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address _token = rewardTokens[i];
            _tokens[i] = _token;
            uint256 _amount;
            if (_typeId == affiliateRewardsTypeId) {
                _amount = claimableRebates[_account][_token];
                claimableRebates[_account][_token] = 0;
                _amount = _transferToken(_account, _token, _amount);
                claimedRebates[_account][_token] = claimedRebates[_account][_token].add(_amount);
            } else if (_typeId == traderDiscountsTypeId) {
                _amount = claimableDiscounts[_account][_token];
                claimableDiscounts[_account][_token] = 0;
                _amount = _transferToken(_account, _token, _amount);
                claimedDiscounts[_account][_token] = claimedDiscounts[_account][_token].add(_amount);
            }
            reserveAmounts[_token] = reserveAmounts[_token].sub(_amount);
            _amounts[i] = _amount;
        }
        emit ClaimRewards(_typeId, _account, _tokens, _amounts);
        return (_tokens, _amounts);
    }

    function _claimable(address _account, uint256 _typeId) internal view returns (address[] memory, uint256[] memory) {
        address[] memory _tokens = new address[](rewardTokens.length);
        uint256[] memory _amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address _token = rewardTokens[i];
            _tokens[i] = _token;
            if (_typeId == affiliateRewardsTypeId) {
                _amounts[i] = claimableRebates[_account][_token];
            } else if (_typeId == traderDiscountsTypeId) {
                _amounts[i] = claimableDiscounts[_account][_token];
            }
        }
        return (_tokens, _amounts);
    }

    function _transferToken(address _account, address _token, uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "insufficient inventory");
        token.safeTransfer(_account, _amount);

        return _amount;
    }


    function depositTokens(address[] memory _tokens, uint256[] memory _amounts) external {
        _onlyHandler();
        require(_tokens.length == _amounts.length, "Invalid input: tokens and amounts length mismatch");
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_amounts[i] > 0) {
                IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), _amounts[i]);
            }
        }
        emit DepositTokens(msg.sender, _tokens, _amounts);
    }

    function withdrawAllTokens(address _token, address _receiver) external {
        _onlyGov();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_receiver, balance);
    }

    function withdrawTokens(address _token, uint256 _amount, address _receiver) external {
        _onlyGov();
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function _onlyGov() private view {
        require(msg.sender == gov, "forbidden");
    }

    function _onlyHandler() private view {
        require(isHandler[msg.sender], "forbidden");
    }
}