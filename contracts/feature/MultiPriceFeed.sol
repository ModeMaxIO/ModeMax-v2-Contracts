// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "../oracle/interfaces/IPriceFeedV2.sol";
import "../core/interfaces/IPositionRouter.sol";
import "../access/Governable.sol";
import {PositionManager} from "../core/PositionManager.sol";

pragma solidity 0.6.12;

contract MultiPriceFeed is Governable {
    using SafeMath for uint256;

    uint256 public minBlockDelayKeeper;
    uint256 public minTimeDelayPublic;
    uint256 public maxTimeDelay;

    address[] public priceFeeds;
    mapping (address => bool) public isUpdater;

    event SetDelayValues(uint256 minBlockDelayKeeper, uint256 minTimeDelayPublic, uint256 maxTimeDelay);

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "MultiPriceFeed: forbidden updates");
        _;
    }

    function setUpdater(address _account, bool _isActive) external onlyGov {
        isUpdater[_account] = _isActive;
    }

    function setPriceFeeds(address[] memory _priceFeeds) external onlyGov {
        require(_priceFeeds.length > 0, "MultiPriceFeed: invalid lengths");
        priceFeeds = _priceFeeds;
    }

    function setDelayValues(uint256 _minBlockDelayKeeper, uint256 _minTimeDelayPublic, uint256 _maxTimeDelay) external onlyGov {
        minBlockDelayKeeper = _minBlockDelayKeeper;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit SetDelayValues(_minBlockDelayKeeper, _minTimeDelayPublic, _maxTimeDelay);
    }

    function setPrices(int192[] memory _answers, uint256 _timestamp) external onlyUpdater {
        _setPrices(_answers, _timestamp);
    }

    function setPricesAndExecute(
        address _positionRouter,
        int192[] memory _answers,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external onlyUpdater {
        _setPrices(_answers, _timestamp);

        IPositionRouter positionRouter = IPositionRouter(_positionRouter);
        uint256 maxEndIndexForIncrease = positionRouter.increasePositionRequestKeysStart().add(_maxIncreasePositions);
        uint256 maxEndIndexForDecrease = positionRouter.decreasePositionRequestKeysStart().add(_maxDecreasePositions);

        if (_endIndexForIncreasePositions > maxEndIndexForIncrease) {
            _endIndexForIncreasePositions = maxEndIndexForIncrease;
        }

        if (_endIndexForDecreasePositions > maxEndIndexForDecrease) {
            _endIndexForDecreasePositions = maxEndIndexForDecrease;
        }

        positionRouter.executeIncreasePositions(_endIndexForIncreasePositions, payable(msg.sender));
        positionRouter.executeDecreasePositions(_endIndexForDecreasePositions, payable(msg.sender));
    }

    function executeIncreaseOrder(
        PositionManager _positionManager,
        int192[] memory _answers,
        uint256 _timestamp,
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver) external onlyUpdater {
        _setPrices(_answers, _timestamp);
        _positionManager.executeIncreaseOrder(_account, _orderIndex, _feeReceiver);
    }

    function executeDecreaseOrder(
        PositionManager _positionManager,
        int192[] memory _answers,
        uint256 _timestamp,
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver) external onlyUpdater {
        _setPrices(_answers, _timestamp);
        _positionManager.executeDecreaseOrder(_account, _orderIndex, _feeReceiver);
    }

    function executeSwapOrder(
        PositionManager _positionManager,
        int192[] memory _answers,
        uint256 _timestamp,
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver) external onlyUpdater {
        _setPrices(_answers, _timestamp);
        _positionManager.executeSwapOrder(_account, _orderIndex, _feeReceiver);
    }

    function liquidatePosition(
        PositionManager _positionManager,
        int192[] memory _answers,
        uint256 _timestamp,
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external onlyUpdater {
        _setPrices(_answers, _timestamp);
        _positionManager.liquidatePosition(_account, _collateralToken, _indexToken, _isLong, _feeReceiver);
    }

    function _setPrices(int192[] memory _answers, uint256 _timestamp) internal {
        require(_answers.length <= priceFeeds.length, "MultiPriceFeed: invalid price lengths");
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