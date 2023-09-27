//SPDX-License-Identifier: UNLCIENSED

pragma solidity >=0.8.0;

contract MockLPXen {
    uint256 public totalReward;

    function addReward(uint256 _rewardAmount) external {
        totalReward += _rewardAmount;
    }
}
