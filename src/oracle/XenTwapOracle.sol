// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPoint} from "../lib/FixedPoint.sol";
import {PairOracleTWAP, PairOracle} from "../lib/PairOracleTWAP.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";

contract XENTwapOracle {
    using PairOracleTWAP for PairOracle;

    uint256 private constant PRECISION = 1e6;

    address public updater;
    uint256 public lastTWAP;

    PairOracle public xenUsdtPair;

    constructor(address _xen, address _xenUsdtPair, address _updater) {
        require(_xen != address(0), "invalid address");
        require(_xenUsdtPair != address(0), "invalid address");
        require(_updater != address(0), "invalid address");
        xenUsdtPair = PairOracle({
            pair: IUniswapV2Pair(_xenUsdtPair),
            token: _xen,
            priceAverage: FixedPoint.uq112x112(0),
            lastBlockTimestamp: 0,
            priceCumulativeLast: 0,
            lastTWAP: 0
        });
        updater = _updater;
    }

    // =============== VIEW FUNCTIONS ===============

    function getCurrentTWAP() public view returns (uint256) {
        // round to 1e12
        return xenUsdtPair.currentTWAP() * PRECISION;
    }

    // =============== USER FUNCTIONS ===============

    function update() external {
        require(msg.sender == updater, "!updater");
        xenUsdtPair.update();
        lastTWAP = xenUsdtPair.lastTWAP * PRECISION;
        emit PriceUpdated(block.timestamp, lastTWAP);
    }

    // ===============  EVENTS ===============
    event PriceUpdated(uint256 timestamp, uint256 price);
}
