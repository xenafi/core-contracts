// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IBurnableERC20} from "../interfaces/IBurnableERC20.sol";

import "../interfaces/IXenaMasterChef.sol";

contract XenaMasterChef is OwnableUpgradeable, ReentrancyGuard, IXenaMasterChef {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardUnclaimed;     // Reward unclaimed
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken;           // Address of LP token contract.
        uint256 allocPoint;        // How many allocation points assigned to this pool. XENA to distribute per second.
        uint256 lastRewardTime;    // Last block number that XENA lock occurs.
        uint256 accSharePerShare;  // Accumulated XENA per share, times 1e18. See below.
        uint256 lockedTime;
        bool isStarted;            // if lastRewardTime has passed
    }

    // The XENA TOKEN!
    address public reward;

    // XENA tokens created per block.
    uint256 public rewardPerSecond; // 50/86400 = 0.000578703704

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => mapping(address => uint256)) public userLastDepositTime;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint_;

    uint256 public startTime;
    uint256 public stopTime;

    address public treasury;

    mapping(address => uint256) public poolIndex;

    uint256 public totalBurned;

    // ADDED VARIABLES (FOR UPGRADEABLE CONTRACTS)

    /* ========== MODIFIERS ========== */
    modifier nonDuplicated(address _lpToken) {
        require(poolIndex[_lpToken] == 0, "nonDuplicated: duplicated");
        _;
    }

    modifier checkPoolEnd() {
        if (block.timestamp >= stopTime) {
            massUpdatePools();
            rewardPerSecond = 0;
            emit UpdateRewardPerSecond(rewardPerSecond);
        }
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function totalAllocPoint() external view returns (uint256) {
        return totalAllocPoint_;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolInfo(uint256 _pid) external view returns (address _lp, uint256 _allocPoint) {
        PoolInfo memory pool = poolInfo[_pid];
        _lp = address(pool.lpToken);
        _allocPoint = pool.allocPoint;
    }

    function getRewardPerSecond() external view returns (uint256) {
        return rewardPerSecond;
    }

    // View function to see pending XENA on frontend.
    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSharePerShare = pool.accSharePerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 _seconds = block.timestamp - pool.lastRewardTime;
            uint256 _shareReward = _seconds * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
            accSharePerShare += _shareReward * 1e18 / lpSupply;
        }
        return user.rewardUnclaimed + (user.amount * accSharePerShare / 1e18) - user.rewardDebt;
    }

    function pendingAllRewards(address _user) external view returns (uint256 _totalPendingRewards) {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _totalPendingRewards = _totalPendingRewards + pendingReward(pid, _user);
        }
    }

    /* ========== GOVERNANCE ========== */
    function initialize(
        address _reward, // XENA
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _stopTime
    ) external initializer {
        OwnableUpgradeable.__Ownable_init();

        reward = _reward;
        rewardPerSecond = _rewardPerSecond;

        startTime = _startTime; // 1692878540: Thu, 24 Aug 2023 12:02:20 GMT
        stopTime = _stopTime; // _startTime + 30 days;
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(_rewardPerSecond <= 0.0001145 ether, "too high rate"); // <= 10 token per day
        massUpdatePools();
        rewardPerSecond = _rewardPerSecond;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(uint256 _allocPoint, address _lpToken, uint256 _lastRewardTime, uint256 _lockedTime) external onlyOwner nonDuplicated(_lpToken) {
        require(_allocPoint <= 100000, "too high allocation point"); // <= 100x
        require(_lockedTime <= 30 days, "locked time is too long");
        massUpdatePools();
        if (block.timestamp < startTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = startTime;
            } else {
                if (_lastRewardTime < startTime) {
                    _lastRewardTime = startTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= startTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
                lpToken : _lpToken,
                allocPoint : _allocPoint,
                lastRewardTime : _lastRewardTime,
                accSharePerShare : 0,
                lockedTime : _lockedTime,
                isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint_ += _allocPoint;
        }
        poolIndex[_lpToken] = poolInfo.length;
    }

    // Update the given pool's XENA allocation point and deposit fee. Can only be called by the owner.
    function setPool(uint256 _pid, uint256 _allocPoint, uint256 _lockedTime) public onlyOwner {
        require(_allocPoint <= 100000, "too high allocation point"); // <= 100x
        require(_lockedTime <= 30 days, "locked time is too long");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint_ = totalAllocPoint_ - pool.allocPoint + _allocPoint;
        }
        pool.allocPoint = _allocPoint;
        pool.lockedTime = _lockedTime;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint_ += pool.allocPoint;
        }
        if (totalAllocPoint_ > 0) {
            uint256 _seconds = block.timestamp - pool.lastRewardTime;
            uint256 _shareReward = _seconds * rewardPerSecond * pool.allocPoint / totalAllocPoint_;
            pool.accSharePerShare += _shareReward * 1e18 / lpSupply;
        }
        pool.lastRewardTime = block.timestamp;
    }

    function _harvestReward(uint256 _pid, address _account, bool _burnReward) internal {
        UserInfo memory user = userInfo[_pid][_account];
        PoolInfo memory pool = poolInfo[_pid];
        uint256 _pending = (user.amount * pool.accSharePerShare / 1e18) - user.rewardDebt;
        if (_pending > 0) {
            if (_burnReward) {
                _sacrificeReward(_pid, _account, _pending);
            } else {
                _transferReward(_pid, _account, _pending);
            }
            userLastDepositTime[_pid][_account] = block.timestamp;
        }
    }

    function _deposit_for(address _account, uint256 _pid, uint256 _amount) internal nonReentrant checkPoolEnd returns (uint256 _depositedAmount) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        updatePool(_pid);
        if (user.amount > 0) {
            _harvestReward(_pid, _account, false);
        }
        if (_amount > 0) {
            IERC20 _lpToken = IERC20(pool.lpToken);
            uint256 _before = _lpToken.balanceOf(address(this));
            _lpToken.safeTransferFrom(_account, address(this), _amount);
            uint256 _after = _lpToken.balanceOf(address(this));
            _amount = _after - _before; // fix issue of deflation token
            if (_amount > 0) {
                user.amount += _amount;
                userLastDepositTime[_pid][_account] = block.timestamp;
            }
        }
        user.rewardDebt = user.amount * pool.accSharePerShare / 1e18;
        emit Deposit(_account, _pid, _amount);
        return _amount;
    }

    // Deposit LP tokens to MasterChef for XENA allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        _deposit_for(_msgSender(), _pid, _amount);
    }

    function depositFor(address _account, uint256 _amount) external override {
        address _lpToken = msg.sender;
        uint256 _pid = poolIndex[_lpToken];
        require(_pid > 0, "pool does not exist");
        _deposit_for(_account, _pid - 1, _amount);
    }

    function canWithdraw(uint256 _pid, address _account) public view returns (bool) {
        return block.timestamp >= unfrozenDepositTime(_pid, _account);
    }

    function unfrozenDepositTime(uint256 _pid, address _account) public view returns (uint256) {
        return userLastDepositTime[_pid][_account] + poolInfo[_pid].lockedTime;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        _withdraw(msg.sender, _pid, _amount);
    }

    function withdrawAll(uint256 _pid) external {
        _withdraw(msg.sender, _pid, userInfo[_pid][msg.sender].amount);
    }

    function _withdraw(address _account, uint256 _pid, uint256 _amount) internal nonReentrant checkPoolEnd {
        require(_amount == 0 || canWithdraw(_pid, _account), "still locked");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        if (user.amount > 0) {
            _harvestReward(_pid, _account, _amount > 0 && pool.lockedTime > 0);
        }
        if (_amount > 0) {
            user.amount -= _amount;
            IERC20(pool.lpToken).safeTransfer(_account, _amount);
        }
        user.rewardDebt = user.amount * pool.accSharePerShare / 1e18;
        emit Withdraw(_account, _pid, _amount);
    }

    function withdrawAndUnlockFor(address _account) external override {
        address _lpToken = msg.sender;
        uint256 _pid = poolIndex[_lpToken];
        require(_pid > 0, "pool does not exist");
        _withdraw(_account, _pid - 1, userInfo[_pid - 1][_account].amount);
    }

    function harvestAllRewards() external {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (userInfo[pid][msg.sender].amount > 0) {
                _withdraw(msg.sender, pid, 0);
            }
        }
    }

    function harvestRewards(uint256[] memory _pids) external {
        uint256 length = _pids.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 _pid = _pids[i];
            if (userInfo[_pid][msg.sender].amount > 0) {
                _withdraw(msg.sender, _pid, 0);
            }
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        // anti cheat (by claim reward and use this function immediately to avoid sacrificing reward
        require(canWithdraw(_pid, msg.sender), "still locked");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardUnclaimed = 0;
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    function _transferReward(uint256 _pid, address _account, uint256 _amount) internal {
        if (_amount > 0) {
            UserInfo storage user = userInfo[_pid][_account];
            uint256 _rewardUnclaimed = user.rewardUnclaimed;
            if (_rewardUnclaimed > 0) {
                _amount += _rewardUnclaimed;
            }
            IERC20 _reward = IERC20(reward);
            uint256 _balance = _reward.balanceOf(address(this));
            if (_amount > _balance) {
                _reward.transfer(_account, _balance);
                uint256 _amountLeft = _amount - _balance;
                user.rewardUnclaimed = _amountLeft;
                emit RewardPaid(_account, _pid, _balance);
                emit RewardUnclaimed(_account, _pid, _amountLeft);
            } else {
                _reward.transfer(_account, _amount);
                emit RewardPaid(_account, _pid, _amount);
                if (_rewardUnclaimed > 0) {
                    user.rewardUnclaimed = 0;
                }
            }
        }
    }

    function _sacrificeReward(uint256 _pid, address _account, uint256 _amount) internal {
        if (_amount > 0) {
            address _reward = reward;
            uint256 _balance = IERC20(_reward).balanceOf(address(this));
            if (_balance > 0) {
                if (_amount > _balance) {
                    IBurnableERC20(_reward).burn(_balance);
                    totalBurned += _balance;
                    emit RewardSacrificed(_account, _pid, _balance);
                } else {
                    IBurnableERC20(_reward).burn(_amount);
                    totalBurned += _amount;
                    emit RewardSacrificed(_account, _pid, _amount);
                }
            }
        }
    }

    /* ========== EMERGENCY ========== */
    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        require(poolIndex[address(_token)] == 0, "lpToken");
        require(address(_token) != reward, "reward");
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }

    /* ========== EVENTS ========== */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardSacrificed(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardUnclaimed(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateRewardPerSecond(uint256 rewardPerSecond);
}
