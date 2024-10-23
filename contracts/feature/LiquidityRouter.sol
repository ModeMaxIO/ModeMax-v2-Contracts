// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../core/interfaces/IRouter.sol";
import "../core/interfaces/IMlpManager.sol";
import "../staking/interfaces/IRewardTracker.sol";
import "./BaseLiquidityManager.sol";
import "./interfaces/ILiquidityRouter.sol";
import "../oracle/interfaces/IPriceFeedV2.sol";


contract LiquidityRouter is BaseLiquidityManager, ILiquidityRouter {
    using Address for address;

    struct DepositRequest {
        address account;
        address token;
        uint256 amount;
        uint256 minUsdg;
        uint256 minLp;
        uint256 executionFee;
        bool hasCollateralInETH;
        uint256 blockNumber;
        uint256 blockTime;
    }

    struct WithdrawalRequest {
        address account;
        address token;
        uint256 lpAmount;
        uint256 minOut;
        address receiver;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
    }

    uint256 public minExecutionFee;
    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;
    bool public checkBuffer;

    mapping (address => bool) public isLiquidityKeeper;

    bytes32[] public override depositRequestKeys;
    bytes32[] public override withdrawalRequestKeys;

    uint256 public override depositRequestKeysStart;
    uint256 public override withdrawalRequestKeysStart;

    mapping (address => uint256) public depositIndex;
    mapping (bytes32 => DepositRequest) public depositRequests;

    mapping (address => uint256) public withdrawalIndex;
    mapping (bytes32 => WithdrawalRequest) public withdrawalRequests;

    address[] public priceFeeds;

    event CreateDeposit(
        address indexed account,
        address token,
        uint256 amount,
        uint256 minUsdg,
        uint256 minLp,
        uint256 executionFee,
        bool hasCollateralInETH,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event CreateWithdrawal(
        address indexed account,
        address token,
        uint256 lpAmount,
        uint256 minOut,
        address receiver,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex,
        uint256 blockNumber,
        uint256 blockTime,
        uint256 gasPrice
    );

    event ExecuteDeposit(
        address indexed account,
        address token,
        uint256 amount,
        uint256 lpAmount,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event ExecuteWithdrawal(
        address indexed account,
        address token,
        uint256 lpAmount,
        uint256 minOut,
        address receiver,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelDeposit(
        address indexed account,
        address token,
        uint256 amount,
        uint256 minUsdg,
        uint256 minLp,
        uint256 executionFee,
        bool hasCollateralInETH,
        uint256 blockGap,
        uint256 timeGap
    );

    event CancelWithdrawal(
        address indexed account,
        address token,
        uint256 lpAmount,
        uint256 minOut,
        address receiver,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );

    event SetLiquidityKeeper(address indexed account, bool isActive);
    event SetMinExecutionFee(uint256 minExecutionFee);
    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);
    event StakeLp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    modifier onlyLiquidityKeeper() {
        require(isLiquidityKeeper[msg.sender], "forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _lp,
        address _lpManager,
        address _feeLpTracker,
        address _stakedLpTracker,
        address _weth,
        uint256 _minExecutionFee
    ) public BaseLiquidityManager(_vault, _router, _lp, _lpManager, _feeLpTracker, _stakedLpTracker, _weth) {
        minExecutionFee = _minExecutionFee;
    }

    function setLiquidityKeeper(address _account, bool _isActive) external onlyAdmin {
        isLiquidityKeeper[_account] = _isActive;
        emit SetLiquidityKeeper(_account, _isActive);
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyAdmin {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay) external onlyAdmin {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    function setPriceFeeds(address[] memory _priceFeeds) external onlyAdmin {
        require(_priceFeeds.length > 0, "invalid pricefeeds lengths");
        priceFeeds = _priceFeeds;
    }

    function setCheckBuffer(bool _isCheck) external onlyAdmin {
        checkBuffer = _isCheck;
    }

    function createDeposit(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLp, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");
        require(_amount > 0, "invalid amount");

        _transferInETH();
        IRouter(router).pluginTransfer(_token, msg.sender, address(this), _amount);

        return _createDeposit(msg.sender, _token, _amount, _minUsdg, _minLp, _executionFee, false);
    }

    function createDepositETH(uint256 _minUsdg, uint256 _minLp, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value > _executionFee, "val");

        _transferInETH();
        uint256 _amount = msg.value.sub(_executionFee);

        return _createDeposit(msg.sender, weth, _amount, _minUsdg, _minLp, _executionFee, true);
    }

    function createWithdrawal(address _token, uint256 _lpAmount, uint256 _minOut, address _receiver, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        _validateToken(_token);
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");
        require(_lpAmount > 0, "invalid lpAmount");
        if (checkBuffer) {
            _validateBufferAmountPrev(_token, _minOut);
        }

        _transferInETH();

        return _createWithdrawal(msg.sender, _token, _lpAmount, _minOut, _receiver, _executionFee);
    }

    function createWithdrawalETH(uint256 _lpAmount, uint256 _minOut, address _receiver, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");
        require(_lpAmount > 0, "invalid lpAmount");
        if (checkBuffer) {
            _validateBufferAmountPrev(weth, _minOut);
        }

        _transferInETH();

        return _createWithdrawal(msg.sender, weth, _lpAmount, _minOut, _receiver, _executionFee);
    }

    function setPricesAndExecute(
        int192[] memory _prices,
        uint256 _timestamp,
        uint256 _endIndexForDeposits,
        uint256 _endIndexForWithdrawals,
        uint256 _maxDeposits,
        uint256 _maxWithdrawals
    ) external override onlyLiquidityKeeper {
        _setPrices(_prices, _timestamp);

        uint256 maxEndIndexForDeposit = depositRequestKeysStart.add(_maxDeposits);
        uint256 maxEndIndexForWithdrawal = withdrawalRequestKeysStart.add(_maxWithdrawals);

        if (_endIndexForDeposits > maxEndIndexForDeposit) {
            _endIndexForDeposits = maxEndIndexForDeposit;
        }

        if (_endIndexForWithdrawals > maxEndIndexForWithdrawal) {
            _endIndexForWithdrawals = maxEndIndexForWithdrawal;
        }

        executeDeposits(_endIndexForDeposits, payable(msg.sender));
        executeWithdrawals(_endIndexForWithdrawals, payable(msg.sender));
    }

    function executeDeposits(uint256 _endIndex, address payable _executionFeeReceiver) public override onlyLiquidityKeeper {

        uint256 index = depositRequestKeysStart;
        uint256 length = depositRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = depositRequestKeys[index];

            try this.executeDeposit(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelDeposit(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete depositRequestKeys[index];
            index++;
        }

        depositRequestKeysStart = index;
    }

    function executeDeposit(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this), "forbidden");

        DepositRequest memory request = depositRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDeposits loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime);
        if (!shouldExecute) { return false; }

        delete depositRequests[_key];

        address account = request.account;
        IERC20(request.token).approve(lpManager, request.amount);
        uint256 lpAmount = IMlpManager(lpManager).addLiquidityForAccount(address(this), account, request.token, request.amount, request.minUsdg, request.minLp);
        IRewardTracker(feeLpTracker).stakeForAccount(account, account, lp, lpAmount);
        IRewardTracker(stakedLpTracker).stakeForAccount(account, account, feeLpTracker, lpAmount);

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit StakeLp(account, lpAmount);
        emit ExecuteDeposit(request.account, request.token, request.amount, lpAmount, request.executionFee, block.number.sub(request.blockNumber), block.timestamp.sub(request.blockTime));

        return true;
    }

    function cancelDeposit(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this), "forbidden");

        DepositRequest memory request = depositRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDeposits loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber);
        if (!shouldCancel) { return false; }

        delete depositRequests[_key];

        if (request.hasCollateralInETH) {
            _transferOutETHWithGasLimitFallbackToWeth(request.amount, payable(request.account));
        } else {
            IERC20(request.token).safeTransfer(request.account, request.amount);
        }

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit CancelDeposit(
            request.account,
            request.token,
            request.amount,
            request.minUsdg,
            request.minLp,
            request.executionFee,
            request.hasCollateralInETH,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }

    function executeWithdrawals(uint256 _endIndex, address payable _executionFeeReceiver) public override onlyLiquidityKeeper {

        uint256 index = withdrawalRequestKeysStart;
        uint256 length = withdrawalRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }

        while (index < _endIndex) {
            bytes32 key = withdrawalRequestKeys[index];

            try this.executeWithdrawal(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelWithdrawal(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete withdrawalRequestKeys[index];
            index++;
        }

        withdrawalRequestKeysStart = index;
    }

    function executeWithdrawal(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this), "forbidden");

        WithdrawalRequest memory request = withdrawalRequests[_key];
        if (request.account == address(0)) { return true; }

        bool shouldExecute = _validateExecution(request.blockNumber, request.blockTime);
        if (!shouldExecute) { return false; }

        delete withdrawalRequests[_key];

        address account = request.account;
        IRewardTracker(stakedLpTracker).unstakeForAccount(account, feeLpTracker, request.lpAmount, account);
        IRewardTracker(feeLpTracker).unstakeForAccount(account, lp, request.lpAmount, account);

        uint256 amountOut = 0;
        if (request.token == weth) {
            amountOut = IMlpManager(lpManager).removeLiquidityForAccount(account, request.token, request.lpAmount, request.minOut, address(this));
            IWETH(weth).withdraw(amountOut);
            payable(request.receiver).sendValue(amountOut);
        } else {
            amountOut = IMlpManager(lpManager).removeLiquidityForAccount(account, request.token, request.lpAmount, request.minOut, request.receiver);
        }

        if (checkBuffer) {
            _validateBufferAmount(request.token);
        }

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit UnstakeGlp(account, request.lpAmount);
        emit ExecuteWithdrawal(request.account, request.token, request.lpAmount, amountOut, request.receiver, request.executionFee,
            block.number.sub(request.blockNumber), block.timestamp.sub(request.blockTime));

        return true;
    }

    function cancelWithdrawal(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this), "forbidden");

        WithdrawalRequest memory request = withdrawalRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeDeposits loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        bool shouldCancel = _validateCancellation(request.blockNumber);
        if (!shouldCancel) { return false; }

        delete withdrawalRequests[_key];

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit CancelWithdrawal(
            request.account,
            request.token,
            request.lpAmount,
            request.minOut,
            request.receiver,
            request.executionFee,
            block.number.sub(request.blockNumber),
            block.timestamp.sub(request.blockTime)
        );

        return true;
    }

    function getRequestQueueLengths() external view override returns (uint256, uint256, uint256, uint256) {
        return (
            depositRequestKeysStart,
            depositRequestKeys.length,
            withdrawalRequestKeysStart,
            withdrawalRequestKeys.length
        );
    }


    function _createDeposit(address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minLp, uint256 _executionFee, bool _hasCollateralInETH) internal returns (bytes32) {
        DepositRequest memory request = DepositRequest(_account, _token, _amount, _minUsdg, _minLp, _executionFee, _hasCollateralInETH, block.number, block.timestamp);

        (uint256 index, bytes32 requestKey) = _storeDepositRequest(request);
        emit CreateDeposit(_account, _token, _amount, _minUsdg, _minLp, _executionFee, _hasCollateralInETH, index, depositRequestKeys.length - 1, block.number, block.timestamp, tx.gasprice);

        return requestKey;
    }

    function _createWithdrawal(address _account, address _token, uint256 _lpAmount, uint256 _minOut, address _receiver, uint256 _executionFee) internal returns (bytes32) {
        WithdrawalRequest memory request = WithdrawalRequest(_account, _token, _lpAmount, _minOut, _receiver, _executionFee, block.number, block.timestamp);

        (uint256 index, bytes32 requestKey) = _storeWithdrawalRequest(request);
        emit CreateWithdrawal(_account, _token, _lpAmount, _minOut, _receiver, _executionFee, index, withdrawalRequestKeys.length - 1, block.number, block.timestamp, tx.gasprice);

        return requestKey;
    }

    function _storeDepositRequest(DepositRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = depositIndex[account].add(1);
        depositIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        depositRequests[key] = _request;
        depositRequestKeys.push(key);

        return (index, key);
    }

    function _storeWithdrawalRequest(WithdrawalRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = withdrawalIndex[account].add(1);
        withdrawalIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        withdrawalRequests[key] = _request;
        withdrawalRequestKeys.push(key);

        return (index, key);
    }

    function _validateExecution(uint256 _blockNumber, uint256 _blockTime) internal view returns (bool) {
        if (_blockTime.add(maxTimeDelay) <= block.timestamp) {
            revert("expired");
        }

        return _validateExecutionOrCancellation(_blockNumber);
    }

    function _validateCancellation(uint256 _positionBlockNumber) internal view returns (bool) {
        return _validateExecutionOrCancellation(_positionBlockNumber);
    }

    function _validateExecutionOrCancellation(uint256 _blockNumber) internal view returns (bool) {
        bool isKeeperCall = msg.sender == address(this) || isLiquidityKeeper[msg.sender];

        if (!isKeeperCall) {
            revert("forbidden: not keeper");
        }

        return _blockNumber.add(minBlockDelayKeeper) <= block.number;
    }

    function getRequestKey(address _account, uint256 _index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index));
    }

    function _setPrices(int192[] memory _answers, uint256 _timestamp) internal {
        require(_answers.length <= priceFeeds.length, "invalid price lengths");
        require(_timestamp.add(maxTimeDelay) > block.timestamp, "prices expired");

        for (uint256 i = 0; i < _answers.length; i++) {
            int192 price = _answers[i];
            if (price > 0) {
                int192[] memory prices = new int192[](1);
                prices[0] = price;

                IPriceFeedV2(priceFeeds[i]).setLatestAnswer(prices);
            }
        }
    }

}