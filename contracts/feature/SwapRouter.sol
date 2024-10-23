// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/math/SafeMath.sol";
import "../libraries/token/SafeERC20.sol";
import "../access/Governable.sol";
import "../oracle/interfaces/IPriceFeedV2.sol";
import "./interfaces/ISwapRouter.sol";
import "../core/interfaces/IRouter.sol";
import "../core/interfaces/IVault.sol";
import "../tokens/interfaces/IWETH.sol";

contract SwapRouter is ReentrancyGuard, Governable, ISwapRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    struct SwapRequest {
        address account;
        address[] path;
        uint256 amountIn;
        uint256 mintOut;
        address receiver;
        uint256 executionFee;
    }

    uint256 public ethTransferGasLimit = 500 * 1000;
    address public admin;
    address public weth;
    address public vault;
    address public usdg;
    uint256 public minExecutionFee;
    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;
    uint256 public maxIterations;

    mapping (address => bool) public isSwapKeeper;

    uint256 public override swapRequestKeysStart;
    bytes32[] public override swapRequestKeys;
    mapping (address => uint256) public swapIndex;
    mapping (bytes32 => SwapRequest) public swapRequests;    

    address[] public priceFeeds;

    event CreateSwap(
        address indexed account,
        address[] path,
        uint256 amountIn,
        uint256 mintOut,
        address receiver,
        uint256 executionFee,
        uint256 index,
        uint256 queueIndex
    );

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    event CancelSwap(
        address indexed account,
        address[] path,
        uint256 amountIn,
        uint256 mintOut,
        address receiver,
        uint256 executionFee
    );

    event SetAdmin(address admin);
    event SetSwapKeeper(address indexed account, bool isActive);
    event SetMinExecutionFee(uint256 minExecutionFee);
    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);

    modifier onlyAdmin() {
        require(msg.sender == admin, "forbidden");
        _;
    }

    modifier onlySwapKeeper() {
        require(isSwapKeeper[msg.sender], "forbidden");
        _;
    }

    constructor(
        address _weth,
        address _vault,
        address _usdg,
        uint256 _minExecutionFee
    ) public {
        require(_weth != address(0), "invalid weth");
        require(_vault != address(0), "invalid vault");
        require(_usdg != address(0), "invalid usdg");
        weth = _weth;
        vault = _vault;
        usdg = _usdg;
        minExecutionFee = _minExecutionFee;
        admin = msg.sender;
        maxIterations = 5;
    }

    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    function setSwapKeeper(address _account, bool _isActive) external onlyAdmin {
        isSwapKeeper[_account] = _isActive;
        emit SetSwapKeeper(_account, _isActive);
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyAdmin {
        minExecutionFee = _minExecutionFee;
        emit SetMinExecutionFee(_minExecutionFee);
    }

    function setPriceFeeds(address[] memory _priceFeeds) external onlyAdmin {
        require(_priceFeeds.length > 0, "invalid pricefeeds lengths");
        priceFeeds = _priceFeeds;
    }

    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay) external onlyAdmin {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    function setMaxIterations(uint256 _maxIterations) external onlyAdmin {
        maxIterations = _maxIterations;
    }

    function createSwap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value == _executionFee, "val");
        require(_amountIn > 0, "invalid amount");

        _transferInETH();
        IERC20(_path[0]).safeTransferFrom(_sender(), address(this), _amountIn);

        return _createSwap(_sender(), _path, _amountIn, _minOut, _receiver, _executionFee);
    }

    function createSwapETHToTokens(address[] memory _path, uint256 _minOut, address _receiver, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_path[0] == weth, "invalid _path");
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value > _executionFee, "val");

        _transferInETH();
        uint256 _amountIn = msg.value.sub(_executionFee);

        return _createSwap(_sender(), _path, _amountIn, _minOut, _receiver, _executionFee);
    }

    function createSwapTokensToETH(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver, uint256 _executionFee) external payable nonReentrant returns (bytes32) {
        require(_path[_path.length - 1] == weth, "invalid _path");
        require(_executionFee >= minExecutionFee, "fee");
        require(msg.value >= _executionFee, "val");
        require(_amountIn > 0, "invalid amount");

        _transferInETH();
        IERC20(_path[0]).safeTransferFrom(_sender(), address(this), _amountIn);

        return _createSwap(_sender(), _path, _amountIn, _minOut, _receiver, _executionFee);
    }

    function setPricesAndExecute(
        int192[] memory _prices,
        uint256 _timestamp,
        uint256 _endIndexForSwaps,
        uint256 _maxSwaps
    ) external override onlySwapKeeper {
        _setPrices(_prices, _timestamp);

        uint256 maxEndIndexForSwap = swapRequestKeysStart.add(_maxSwaps);

        if (_endIndexForSwaps > maxEndIndexForSwap) {
            _endIndexForSwaps = maxEndIndexForSwap;
        }

        executeSwaps(_endIndexForSwaps, payable(msg.sender));
    }

    function executeSwaps(uint256 _endIndex, address payable _executionFeeReceiver) public override onlySwapKeeper {

        uint256 index = swapRequestKeysStart;
        uint256 length = swapRequestKeys.length;

        if (index >= length) { return; }

        if (_endIndex > length) {
            _endIndex = length;
        }
        uint256 maxIndex = index.add(maxIterations);
        if (_endIndex > maxIndex) {
            _endIndex = maxIndex;
        }

        while (index < _endIndex) {
            bytes32 key = swapRequestKeys[index];

            try this.executeSwap(key, _executionFeeReceiver) returns (bool _wasExecuted) {
                if (!_wasExecuted) { break; }
            } catch {
                // wrap this call in a try catch to prevent invalid cancels from blocking the loop
                try this.cancelSwap(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                    if (!_wasCancelled) { break; }
                } catch {}
            }

            delete swapRequestKeys[index];
            index++;
        }

        swapRequestKeysStart = index;
    }

    function executeSwap(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this), "forbidden");

        SwapRequest memory request = swapRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeSwaps loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        delete swapRequests[_key];

        address[] memory _path =  request.path;
        uint256 _amountIn = request.amountIn;
        IERC20(_path[0]).safeTransfer(vault, _amountIn);

        uint256 _amountOut = 0;
        uint256 _minOut = request.mintOut;
        address _receiver = request.receiver;
        if (_path[_path.length - 1] == weth) {
            _amountOut = _swap(_path, _minOut, address(this));
            _transferOutETH(_amountOut, payable(_receiver));
        } else {
            _amountOut = _swap(_path, _minOut, _receiver);
        }

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit Swap(request.account, _path[0], _path[_path.length - 1], _amountIn, _amountOut);

        return true;
    }

    function cancelSwap(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        require(msg.sender == address(this) || isSwapKeeper[msg.sender], "forbidden");

        SwapRequest memory request = swapRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeSwaps loop will continue executing the next request
        if (request.account == address(0)) { return true; }

        delete swapRequests[_key];

        address[] memory _path = request.path;
        if (_path[0] == weth) {
            _transferOutETHWithGasLimitFallbackToWeth(request.amountIn, payable(request.account));
        } else {
            IERC20(_path[0]).safeTransfer(request.account, request.amountIn);
        }

        _transferOutETHWithGasLimitFallbackToWeth(request.executionFee, _executionFeeReceiver);

        emit CancelSwap(request.account, request.path, request.amountIn, request.mintOut, request.receiver, request.executionFee);
        return true;
    }

    function getRequestQueueLengths() external view override returns (uint256, uint256) {
        return (
            swapRequestKeysStart,
            swapRequestKeys.length
        );
    }

    function _createSwap(address _account, address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver, uint256 _executionFee) internal returns (bytes32) {
        require(_path.length == 2 || _path.length == 3, "Invalid path length");
        SwapRequest memory request = SwapRequest(_account, _path, _amountIn, _minOut, _receiver, _executionFee);

        (uint256 index, bytes32 requestKey) = _storeSwapRequest(request);
        emit CreateSwap(_account, _path, _amountIn, _minOut, _receiver, _executionFee, index, swapRequestKeys.length - 1);

        return requestKey;
    }

    function _storeSwapRequest(SwapRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = swapIndex[account].add(1);
        swapIndex[account] = index;
        bytes32 key = getRequestKey(account, index);

        swapRequests[key] = _request;
        swapRequestKeys.push(key);

        return (index, key);
    }

    function _swap(address[] memory _path, uint256 _minOut, address _receiver) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this));
            IERC20(_path[1]).safeTransfer(vault, midOut);
            return _vaultSwap(_path[1], _path[2], _minOut, _receiver);
        }

        revert("invalid _path.length");
    }

    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) private returns (uint256) {
        uint256 amountOut;

        if (_tokenOut == usdg) { // buyUSDG
            amountOut = IVault(vault).buyUSDG(_tokenIn, _receiver);
        } else if (_tokenIn == usdg) { // sellUSDG
            amountOut = IVault(vault).sellUSDG(_tokenOut, _receiver);
        } else { // swap
            amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        }

        require(amountOut >= _minOut, "insufficient amountOut");
        return amountOut;
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

    function _sender() private view returns (address) {
        return msg.sender;
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _transferOutETHWithGasLimitFallbackToWeth(uint256 _amountOut, address payable _receiver) internal {
        IWETH _weth = IWETH(weth);
        _weth.withdraw(_amountOut);

        // re-assign ethTransferGasLimit since only local variables
        // can be used in assembly calls
        uint256 _ethTransferGasLimit = ethTransferGasLimit;

        bool success;
        // use an assembly call to avoid loading large data into memory
        // input mem[in…(in+insize)]
        // output area mem[out…(out+outsize))]
        assembly {
            success := call(
                _ethTransferGasLimit, // gas limit
                _receiver, // receiver
                _amountOut, // value
                0, // in
                0, // insize
                0, // out
                0 // outsize
            )
        }

        if (success) { return; }

        // if the transfer failed, re-wrap the token and send it to the receiver
        _weth.deposit{ value: _amountOut }();
        IERC20(weth).safeTransfer(address(_receiver), _amountOut);
    }
}