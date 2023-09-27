// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface ILockingEscrow {
    function locked__of(address _addr) external view returns (uint256);

    function locked__end() external view returns (uint256);

    function voting_power(uint256 _value) external view returns (uint256);

    function deposit_for(address _addr, uint256 _value) external;

    function lock(uint256 _value) external;

    function lockAndStake(address _chef, uint256 _value) external;

    function withdraw() external;

    function unstakeAndWithdraw(address _chef) external;
}
