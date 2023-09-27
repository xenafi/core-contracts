// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/ILockingEscrow.sol";
import "../interfaces/IXenaMasterChef.sol";

contract FixedPeriodLockingEscrowToken is ERC20Burnable, Ownable, ReentrancyGuard, ILockingEscrow {
    using SafeERC20 for IERC20;

    address public lockedToken;
    address public treasury;

    uint256 public unlockedTimestamp;
    uint256 public earlyWithdrawFeeRate;

    uint256 public MAXTIME = 100 days;

    struct LockedBalance {
        uint256 amount;
        uint256 escrowAmount;
    }

    mapping(address => LockedBalance) public locked;
    mapping(address => uint256) public mintedForLock;

    event Deposit(address indexed provider, uint256 value, uint256 locktime, uint256 timestamp);
    event Withdraw(address indexed provider, uint256 value, uint256 timestamp);
    event UpdateTreasury(address _treasury);
    event UpdateEarlyWithdrawFeeRate(uint256 newValue);

    constructor(string memory _name, string memory _symbol, address _lockedToken, address _treasury, uint256 _unlockedTimestamp) ERC20(_name, _symbol) {
        lockedToken = address(_lockedToken);
        treasury = _treasury;
        unlockedTimestamp = _unlockedTimestamp;
        earlyWithdrawFeeRate = 5000; // 50%
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit UpdateTreasury(_treasury);
    }

    function setEarlyWithdrawFeeRate(uint256 _earlyWithdrawFeeRate) external onlyOwner {
        require(_earlyWithdrawFeeRate <= 5000, "too high"); // <= 50%
        earlyWithdrawFeeRate = _earlyWithdrawFeeRate;
        emit UpdateEarlyWithdrawFeeRate(_earlyWithdrawFeeRate);
    }

    function setUnlockedTimestamp(uint256 _unlockedTimestamp) external onlyOwner {
        require(_unlockedTimestamp < unlockedTimestamp, "too late");
        unlockedTimestamp = _unlockedTimestamp;
    }

    function burn(uint256 _amount) public override {
        _burn(_msgSender(), _amount);
    }

    function locked__of(address _addr) external override view returns (uint256) {
        return locked[_addr].amount;
    }

    function locked__end() external override view returns (uint256) {
        return unlockedTimestamp;
    }

    function voting_power(uint256 _value) public override view returns (uint256) {
        uint256 _unlock_time = unlockedTimestamp;
        if (_unlock_time <= block.timestamp) return 0;
        uint256 _lockedSeconds = _unlock_time - block.timestamp;
        if (_lockedSeconds >= MAXTIME) return _value;
        return _value * _lockedSeconds / MAXTIME;
    }

    function deposit_for(address _addr, uint256 _value) external override {
        require(_value > 0, "zero");
        _deposit_for(_addr, _value);
    }

    function lock(uint256 _value) external override {
        require(_value > 0, "zero");
        _deposit_for(_msgSender(), _value);
    }

    function lockAndStake(address _chef, uint256 _value) external override {
        require(_value > 0, "zero");
        uint256 _vp = _deposit_for(_msgSender(), _value);
        _approve(_msgSender(), _chef, _vp);
        IXenaMasterChef(_chef).depositFor(_msgSender(), _vp);
    }

    function _deposit_for(address _addr, uint256 _value) internal nonReentrant returns (uint256 _escrowAmount) {
        LockedBalance storage _locked = locked[_addr];
        uint256 _vp = voting_power(_value);
        require(_vp > 0, "No benefit to lock");
        _locked.amount += _value;
        _locked.escrowAmount += _vp;
        IERC20(lockedToken).safeTransferFrom(_msgSender(), address(this), _value);
        _mint(_addr, _vp);

        emit Deposit(_addr, _locked.amount, unlockedTimestamp, block.timestamp);
        return _vp;
    }

    function _withdraw(uint256 _earlyWithdrawFeeRate) internal nonReentrant {
        LockedBalance storage _locked = locked[_msgSender()];
        uint256 _amount = _locked.amount;
        require(_amount > 0, "Nothing to withdraw");
        if (_earlyWithdrawFeeRate > 0) {
            uint256 _fee = _amount * _earlyWithdrawFeeRate / 10000;
            IERC20(lockedToken).safeTransfer(treasury, _fee);
            _amount -= _fee;
        } else {
            require(block.timestamp >= unlockedTimestamp, "The lock didn't expire");
        }
        uint256 _escrowAmount = _locked.escrowAmount;
        _locked.amount = 0;
        _burn(_msgSender(), _escrowAmount);
        _locked.escrowAmount = 0;
        IERC20(lockedToken).safeTransfer(_msgSender(), _amount);
        emit Withdraw(_msgSender(), _amount, block.timestamp);
    }

    function withdraw() external override {
        _withdraw(0);
    }

    function unstakeAndWithdraw(address _chef) external override {
        IXenaMasterChef(_chef).withdrawAndUnlockFor(_msgSender());
        _withdraw(0);
    }

    // This will charge PENALTY if lock is not expired yet
    function emergencyWithdraw() external {
        _withdraw(earlyWithdrawFeeRate);
    }

    // This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(address _token, address _to, uint256 _amount) external onlyOwner {
        require(_token != lockedToken, "core");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
