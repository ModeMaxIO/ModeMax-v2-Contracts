// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "./interfaces/IAdapterPyth.sol";

contract AdapterPyth is IAdapterPyth {
    address public pythContract;

    constructor(address contractAddress) {
        pythContract = contractAddress;
    }

    function latestPrice(bytes32 priceFeedId, uint8 decimals) external view returns (
        int256 price,
        uint256 timestamp
    ) {
        IPyth pyth = IPyth(pythContract);
        try
            pyth.getPrice(priceFeedId)
        returns (PythStructs.Price memory ret) {
            price = priceDecimals(ret.price, ret.expo, decimals);
            timestamp = ret.publishTime;
        } catch {
            try
                pyth.getEmaPriceUnsafe(priceFeedId)
            returns (PythStructs.Price memory ret) {
                price = priceDecimals(ret.price, ret.expo, decimals);
                timestamp = ret.publishTime;
            } catch {}
        }
    }

    function priceDecimals(int256 price, int32 expo, uint8 decimals) private pure returns (int256) {
        if (decimals > uint32(-expo)) {
            price = price * int256(10 ** (decimals-uint8(uint32(-expo))));
        } else if (decimals < uint32(-expo)) {
            price = price / int256(10 ** (uint8(uint32(-expo))-decimals));
        }
        return price;
    }

    function getPrice(bytes32 priceId) public view returns (PythStructs.Price memory) {
        IPyth pyth = IPyth(pythContract);

//        bytes32 priceId = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
        return pyth.getPrice(priceId);
    }

    function getEmaPriceUnsafe(bytes32 priceId) public view returns (PythStructs.Price memory) {
        IPyth pyth = IPyth(pythContract);

//        bytes32 priceId = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
        return pyth.getEmaPriceUnsafe(priceId);
    }

    function getPriceNoOlderThan(bytes32 priceId, uint age) public view returns (PythStructs.Price memory) {
        IPyth pyth = IPyth(pythContract);

//        bytes32 priceId = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
        return pyth.getPriceNoOlderThan(priceId, age);
    }
}