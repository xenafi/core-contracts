// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IXenaMasterChef {
    function depositFor(address _account, uint256 _amount) external;

    function withdrawAndUnlockFor(address _account) external;
}
