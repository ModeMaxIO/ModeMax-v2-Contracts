// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributorMT.sol";
import "./interfaces/IRewardTrackerMT.sol";
import "../access/Governable.sol";

contract RewardTrackerMT is IERC20, ReentrancyGuard, IRewardTrackerMT, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRECISION = 1e30;

    uint8 public constant decimals = 18;

    bool public isInitialized;

    string public name;
    string public symbol;

    address public distributor;
    mapping (address => bool) public isDepositToken;
    mapping (address => mapping (address => uint256)) public override depositBalances;
    mapping (address => uint256) public totalDepositSupply;

    uint256 public override totalSupply;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;

    mapping (address => uint256) cumulativeRewardPerToken;
    mapping (address => uint256) public override stakedAmounts;
    mapping (address => mapping (address => uint256)) public claimableReward;
    mapping (address => mapping (address => uint256)) public previousCumulatedRewardPerToken;
    mapping (address => mapping (address => uint256)) public override cumulativeRewards;
    mapping (address => uint256) public override averageStakedAmounts;

    bool public inPrivateTransferMode;
    bool public inPrivateStakingMode;
    bool public inPrivateClaimingMode;
    mapping (address => bool) public isHandler;

    event Claim(address receiver, address[], uint256[]);

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    function initialize(
        address[] memory _depositTokens,
        address _distributor
    ) external onlyGov {
        require(!isInitialized, "RewardTracker: already initialized");
        isInitialized = true;

        for (uint256 i = 0; i < _depositTokens.length; i++) {
            address depositToken = _depositTokens[i];
            isDepositToken[depositToken] = true;
        }

        distributor = _distributor;
    }

    function setDepositToken(address _depositToken, bool _isDepositToken) external onlyGov {
        isDepositToken[_depositToken] = _isDepositToken;
    }

    function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyGov {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    function setInPrivateStakingMode(bool _inPrivateStakingMode) external onlyGov {
        inPrivateStakingMode = _inPrivateStakingMode;
    }

    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external onlyGov {
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function stake(address _depositToken, uint256 _amount) external override nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _stake(msg.sender, msg.sender, _depositToken, _amount);
    }

    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external override nonReentrant {
        _validateHandler();
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    function unstake(address _depositToken, uint256 _amount) external override nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _unstake(msg.sender, _depositToken, _amount, msg.sender);
    }

    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external override nonReentrant {
        _validateHandler();
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }

        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "RewardTracker: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function tokensPerIntervals() external override view returns (address[] memory, uint256[] memory) {
        return IRewardDistributorMT(distributor).getAllTokensPerIntervals();
    }

    function updateRewards() external override nonReentrant {
        _updateRewards(address(0));
    }

    function claim(address _receiver) external override nonReentrant returns (address[] memory, uint256[] memory) {
        if (inPrivateClaimingMode) { revert("RewardTracker: action not enabled"); }
        return _claim(msg.sender, _receiver);
    }

    function claimForAccount(address _account, address _receiver) external override nonReentrant returns (address[] memory, uint256[] memory) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    struct RewardCalculation {
        uint256 stakedAmount;
        uint256 nextCumulativeRewardPerToken;
        uint256 previousCumulatedRewardPerToken;
        uint256 claimableReward;
    }

    function claimable(address _account) public override view returns (address[] memory, uint256[] memory) {
        uint256 stakedAmount = stakedAmounts[_account];
        uint256 supply = totalSupply;
        (address[] memory _tokens, uint256[] memory _amounts) = IRewardDistributorMT(distributor).pendingRewards();
        address[] memory _claimTokens = new address[](_tokens.length);
        uint256[] memory _claimAmounts = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address _token = _tokens[i];
            _claimTokens[i] = _token;
            uint256 _amount = _amounts[i];

            RewardCalculation memory calc;
            calc.stakedAmount = stakedAmount;
            calc.nextCumulativeRewardPerToken = cumulativeRewardPerToken[_token].add(_amount.mul(PRECISION).div(supply));
            calc.previousCumulatedRewardPerToken = previousCumulatedRewardPerToken[_account][_token];
            calc.claimableReward = claimableReward[_account][_token];

            _claimAmounts[i] = calc.claimableReward.add(
                calc.stakedAmount.mul(calc.nextCumulativeRewardPerToken.sub(calc.previousCumulatedRewardPerToken)).div(PRECISION)
            );
        }
        return (_claimTokens, _claimAmounts);
    }

    function rewardToken() public view returns (address[] memory) {
        return IRewardDistributorMT(distributor).getAllRewardTokens();
    }

    function allCumulativeRewards(address _account) external view override returns (uint256) {
        address[] memory _tokens = rewardToken();
        uint256 total = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            total = total.add(cumulativeRewards[_account][_tokens[i]]);
        }
        return total;
    }

    function _claim(address _account, address _receiver) private returns (address[] memory, uint256[] memory) {
        _updateRewards(_account);

        address[] memory _rewardTokens = rewardToken();
        address[] memory _tokens = new address[](_rewardTokens.length);
        uint256[] memory _amounts = new uint256[](_rewardTokens.length);
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address _token = _rewardTokens[i];
            _tokens[i] = _token;
            uint256 tokenAmount = claimableReward[_account][_token];
            claimableReward[_account][_token] = 0;
            if (tokenAmount > 0) {
                IERC20(_token).safeTransfer(_receiver, tokenAmount);
                _amounts[i] = tokenAmount;
            }
        }

        emit Claim(_account, _tokens, _amounts);
        return (_tokens, _amounts);
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: burn from the zero address");

        balances[_account] = balances[_account].sub(_amount, "RewardTracker: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "RewardTracker: transfer from the zero address");
        require(_recipient != address(0), "RewardTracker: transfer to the zero address");

        if (inPrivateTransferMode) { _validateHandler(); }

        balances[_sender] = balances[_sender].sub(_amount, "RewardTracker: transfer amount exceeds balance");
        balances[_recipient] = balances[_recipient].add(_amount);

        emit Transfer(_sender, _recipient,_amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "RewardTracker: approve from the zero address");
        require(_spender != address(0), "RewardTracker: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "RewardTracker: forbidden");
    }

    function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(isDepositToken[_depositToken], "RewardTracker: invalid _depositToken");

        IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);

        _updateRewards(_account);

        stakedAmounts[_account] = stakedAmounts[_account].add(_amount);
        depositBalances[_account][_depositToken] = depositBalances[_account][_depositToken].add(_amount);
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken].add(_amount);

        _mint(_account, _amount);
    }

    function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(isDepositToken[_depositToken], "RewardTracker: invalid _depositToken");

        _updateRewards(_account);

        uint256 stakedAmount = stakedAmounts[_account];
        require(stakedAmounts[_account] >= _amount, "RewardTracker: _amount exceeds stakedAmount");

        stakedAmounts[_account] = stakedAmount.sub(_amount);

        uint256 depositBalance = depositBalances[_account][_depositToken];
        require(depositBalance >= _amount, "RewardTracker: _amount exceeds depositBalance");
        depositBalances[_account][_depositToken] = depositBalance.sub(_amount);
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken].sub(_amount);

        _burn(_account, _amount);
        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }

    function _updateAccountRewards(
        address _account,
        address _token,
        uint256 stakedAmount,
        uint256 _cumulativeRewardPerToken
    ) private {
        uint256 accountReward = stakedAmount.mul(_cumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[_account][_token])).div(PRECISION);
        uint256 _claimableReward = claimableReward[_account][_token].add(accountReward);

        claimableReward[_account][_token] = _claimableReward;
        previousCumulatedRewardPerToken[_account][_token] = _cumulativeRewardPerToken;

        if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
            uint256 nextCumulativeReward = cumulativeRewards[_account][_token].add(accountReward);

            averageStakedAmounts[_account] = averageStakedAmounts[_account].mul(cumulativeRewards[_account][_token]).div(nextCumulativeReward)
                .add(stakedAmount.mul(accountReward).div(nextCumulativeReward));

            cumulativeRewards[_account][_token] = nextCumulativeReward;
        }
    }

    function _updateRewards(address _account) private {
        (address[] memory _tokens, uint256[] memory _amounts) = IRewardDistributorMT(distributor).distribute();

        uint256 supply = totalSupply;
        for (uint256 i = 0; i < _tokens.length; i++) {
            address _token = _tokens[i];
            uint256 blockReward = _amounts[i];
            uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken[_token];
            if (supply > 0 && blockReward > 0) {
                _cumulativeRewardPerToken = _cumulativeRewardPerToken.add(blockReward.mul(PRECISION).div(supply));
                cumulativeRewardPerToken[_token] = _cumulativeRewardPerToken;
            }

            if (_cumulativeRewardPerToken > 0 && _account != address(0)) {
                _updateAccountRewards(_account, _token, stakedAmounts[_account], _cumulativeRewardPerToken);
            }
        }
    }
}
