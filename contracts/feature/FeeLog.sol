// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "./interfaces/IFeeLog.sol";

contract FeeLog is IFeeLog {
    using SafeMath for uint256;

    address public override gov;
    uint256 public override lastFeesAmount;
    uint256 public override lastTimestamp;

    mapping (address => bool) public override isUpdater;

    event SetGov(address account);

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "Update: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
        lastTimestamp = block.timestamp;
    }

    function setGov(address _gov) external onlyGov {
        require(_gov != address(0), "invalid address");
        gov = _gov;
        emit SetGov(_gov);
    }

    function setUpdater(address _account, bool _isActive) external onlyGov {
        isUpdater[_account] = _isActive;
    }

    function setFeesInfo(uint256 _usdAmount, uint256 _timestamp) external override onlyGov {
        lastFeesAmount = _usdAmount;
        lastTimestamp = _timestamp;
    }

    function distribute(uint256 _usdAmount, uint256 _timestamp) external override onlyUpdater {
        lastFeesAmount = lastFeesAmount.add(_usdAmount);
        lastTimestamp = _timestamp;
    }

    function feesInfo() external view override returns (uint256, uint256) {
        return (lastFeesAmount, lastTimestamp);
    }
}