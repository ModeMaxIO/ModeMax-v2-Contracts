// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../tokens/interfaces/IWETH.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/Address.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IBaseLiquidityManager.sol";
import "../access/Governable.sol";
import "../core/interfaces/IVault.sol";

contract BaseLiquidityManager is IBaseLiquidityManager, ReentrancyGuard, Governable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public ethTransferGasLimit = 500 * 1000;

    address public admin;

    address public vault;
    address public router;
    address public lp;
    address public lpManager;
    address public feeLpTracker;
    address public stakedLpTracker;
    address public weth;

    event SetAdmin(address admin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _lp,
        address _lpManager,
        address _feeLpTracker,
        address _stakedLpTracker,
        address _weth
    ) public {
        vault = _vault;
        router = _router;
        lp = _lp;
        lpManager = _lpManager;
        feeLpTracker = _feeLpTracker;
        stakedLpTracker = _stakedLpTracker;
        weth = _weth;

        admin = msg.sender;
    }

    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
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

    function _validateBufferAmount(address _token) internal view {
        IVault iVault = IVault(vault);
        if (iVault.poolAmounts(_token) < iVault.bufferAmounts(_token)) {
            revert("insufficient poolAmount");
        }
    }

    function _validateBufferAmountPrev(address _token, uint256 _decreaseAmount) internal view {
        IVault iVault = IVault(vault);
        uint256 _poolAmount = iVault.poolAmounts(_token);
        if (_poolAmount < _decreaseAmount || _poolAmount.sub(_decreaseAmount) < iVault.bufferAmounts(_token)) {
            revert("insufficient poolAmount");
        }
    }

    function _validateToken(address _token) internal view {
        require(IVault(vault).whitelistedTokens(_token), "token not whitelisted");
    }
}