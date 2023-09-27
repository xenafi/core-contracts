// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IXENTwapOracle} from "../interfaces/IXENTwapOracle.sol";
import {ILPXen} from "../interfaces/ILPXen.sol";
import {ITradingContest} from "../interfaces/ITradingContest.sol";
import {ITradingIncentiveController} from "../interfaces/ITradingIncentiveController.sol";

/**
 * @title ITradingIncentiveController
 * @notice Tracking protocol fee and calculate incentive reward in a period of time called batch.
 * Once a batch finished, incentive distributed to lpXEN and Ladder
 */
contract TradingIncentiveController is Initializable, OwnableUpgradeable, ITradingIncentiveController {
    /*================= VARIABLES ================*/
    using SafeERC20 for IERC20;

    IERC20 public constant XEN = IERC20(0x6810AB468fFD38Accc787D0119dc20Ba1C9E554F);
    uint256 public constant MIN_EPOCH_DURATION = 1 days;
    uint256 public constant MAX_REWARD_TOKENS = 15_000e18;
    uint256 public constant STEP_REVENUE = 50_000e30;
    uint256 public constant BASE_REVENUE = 100_000e30;
    uint256 public constant STEP_REWARD = 10_000e30;
    uint256 public constant AMOUNT_LOYALTY_REWARD = 5_000e18;

    uint256 public currentEpoch;
    uint256 public lastEpochTimestamp;
    uint256 public epochDuration;
    uint256 public epochFee;

    address public poolHook;
    address public admin;
    IXENTwapOracle public xenOracle;
    ILPXen public lpXen;
    ITradingContest public tradingContest;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _xenOracle, address _poolHook, address _tradingContest, address _lpXen)
        external
        initializer
    {
        require(_xenOracle != address(0), "Invalid address");
        require(_poolHook != address(0), "Invalid address");
        require(_tradingContest != address(0), "Invalid address");
        require(_lpXen != address(0), "Invalid address");

        __Ownable_init();
        xenOracle = IXENTwapOracle(_xenOracle);
        xenOracle.update();
        poolHook = _poolHook;
        tradingContest = ITradingContest(_tradingContest);
        lpXen = ILPXen(_lpXen);
        emit PoolHookSet(_poolHook);
        emit TradingContestSet(_tradingContest);
        emit LPXenSet(_lpXen);
    }

    /*=================== MUTATIVE =====================*/

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function record(uint256 _value) external {
        require(msg.sender == poolHook, "Only poolHook");
        if (block.timestamp >= lastEpochTimestamp) {
            epochFee += _value;
        }
    }

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function allocate() external {
        require(msg.sender == admin, "!Admin");
        require(lastEpochTimestamp > 0, "Not started");

        uint256 _nextEpochTimestamp = lastEpochTimestamp + epochDuration;
        require(block.timestamp >= _nextEpochTimestamp, "now < trigger time");

        xenOracle.update();
        uint256 _twap = xenOracle.lastTWAP();

        XEN.safeIncreaseAllowance(address(lpXen), AMOUNT_LOYALTY_REWARD);
        lpXen.addReward(AMOUNT_LOYALTY_REWARD);

        uint256 _contestRewards;
        if (epochFee >= BASE_REVENUE) {
            uint256 _rewards = ((epochFee - BASE_REVENUE) / STEP_REVENUE + 1) * STEP_REWARD;

            _contestRewards = _rewards / _twap;
            if (_contestRewards > MAX_REWARD_TOKENS - AMOUNT_LOYALTY_REWARD) {
                _contestRewards = MAX_REWARD_TOKENS - AMOUNT_LOYALTY_REWARD;
            }
            XEN.safeIncreaseAllowance(address(tradingContest), _contestRewards);
        }
        tradingContest.addReward(_contestRewards);

        emit Allocated(currentEpoch, epochFee, _contestRewards, AMOUNT_LOYALTY_REWARD);
        epochFee = 0;
        lastEpochTimestamp = _nextEpochTimestamp;

        currentEpoch++;
        emit EpochStarted(currentEpoch, _nextEpochTimestamp);
    }

    /**
     * @inheritdoc ITradingIncentiveController
     */
    function start(uint256 _startTime) external {
        require(lastEpochTimestamp == 0, "started");
        require(_startTime >= block.timestamp, "start time < current time");
        lastEpochTimestamp = _startTime;
        xenOracle.update();
        emit EpochStarted(currentEpoch, _startTime);
    }

    /*================ ADMIN ===================*/

    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        require(_epochDuration >= MIN_EPOCH_DURATION, "must >= MIN_EPOCH_DURATION");
        epochDuration = _epochDuration;
        emit EpochDurationSet(epochDuration);
    }

    function setPoolHook(address _poolHook) external onlyOwner {
        require(_poolHook != address(0), "Invalid address");
        poolHook = _poolHook;
        emit PoolHookSet(_poolHook);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminSet(_admin);
    }

    function withdrawXEN(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        XEN.safeTransfer(_to, _amount);
        emit XENWithdrawn(_to, _amount);
    }

    /*================ EVENTS ===================*/
    event TradingContestSet(address _addr);
    event LPXenSet(address _addr);
    event PoolHookSet(address _addr);
    event OracleSet(address _oracle);
    event Allocated(uint256 _epoch, uint256 _totalFee, uint256 _contestReward, uint256 _loyaltyRewards);
    event XENWithdrawn(address _to, uint256 _amount);
    event EpochDurationSet(uint256 _duration);
    event AdminSet(address _admin);
    event EpochStarted(uint256 _epoch, uint256 _timeStart);
    event LoyaltyRewardSet(uint256 _rewards);
}
