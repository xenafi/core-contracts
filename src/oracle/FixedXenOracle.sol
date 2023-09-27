// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

contract FixedXenOracle {
    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function update() external {}

    function lastTWAP() external view returns (uint256) {
        return price;
    }

    function getCurrentTWAP() external view returns (uint256) {
        return price;
    }
}
