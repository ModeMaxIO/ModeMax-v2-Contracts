// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseTokenBlacklisted.sol";

contract MOX is MintableBaseTokenBlacklisted {
    constructor() public MintableBaseTokenBlacklisted("ModeMax Token", "MOX", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "MOX";
    }
}
