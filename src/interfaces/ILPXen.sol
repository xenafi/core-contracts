// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

/**
 * @notice Xena loyalty token. Mint to trader whenever they take a trade. Auto redeem to XEN when batch completed
 */
interface ILPXen {
    /**
     * @notice accept reward send from IncentiveController
     */
    function addReward(uint256 _rewardAmount) external;

    /**
     * @notice finalize current batch, redeem (burn) all lpXen to XEN
     */
    function allocate() external;

    function epochDuration() external view returns (uint256);
}
