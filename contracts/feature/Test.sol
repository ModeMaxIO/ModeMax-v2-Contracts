// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

contract Test {

    uint256 public num;

    function setNum(uint256 _num) external {
        num = _num;
    }

    function getNum() external view returns (uint256) {
        return num;
    }

}