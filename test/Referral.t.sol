pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/referral/ReferralRegistry.sol";
import "../src/referral/ReferralController.sol";
import "../src/interfaces/IXENTwapOracle.sol";
import {TransparentUpgradeableProxy as Proxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ReferralTest is Test {
    address owner = 0x9Cb2f2c0122a1A8C90f667D1a55E5B45AC8b6086;
    address alice = 0xfC067b2BE205F8e8C85aC653f64C52baa225aCa4;
    address bob = 0x90FbB788b18241a4bBAb4cd5eb839a42FF59D235;
    address dee = 0x462beDFDAFD8681827bf8E91Ce27914cb00CcF83;
    address eve = 0x2E20CFb2f7f98Eb5c9FD31Df41620872C0aef524;
    address proxyAdmin = address(bytes20("proxyAdmin"));
    uint256 private constant REBATE_PRECISION = 1e6;
    address twapOracle = address(bytes20("lvl-twap-oracle"));

    ReferralRegistry referralRegistry;
    ReferralController referralController;
    uint256 lastTimestamp;

    uint256 public epochDuration = 7 days;

    modifier init() {
        test_initialize();
        _;
    }

    function test_initialize() public {
        vm.startPrank(owner);

        Proxy registryProxy = new Proxy(address(new ReferralRegistry()), address(proxyAdmin), new bytes(0));
        referralRegistry = ReferralRegistry(address(registryProxy));
        referralRegistry.initialize();

        Proxy controllerProxy = new Proxy(address(new ReferralController()), address(proxyAdmin), new bytes(0));
        referralController = ReferralController(address(controllerProxy));

        vm.mockCall(twapOracle, abi.encodeWithSelector(IXENTwapOracle.update.selector), new bytes(0));
        referralController.initialize(twapOracle, address(referralRegistry), 7 days);

        referralController.start(block.timestamp);
        (uint64 _startTime, uint64 _endTime,,) = referralController.epochs(referralController.currentEpoch());

        assertEq(_startTime, uint64(block.timestamp));
        assertEq(_endTime, 0);
        referralRegistry.setController(address(referralController));

        referralController.setPoolHook(owner);
        referralController.setDistributor(owner);
        referralController.setOrderHook(owner);

        lastTimestamp = block.timestamp;
        vm.stopPrank();
    }

    event SetChainToClaimRewards(address indexed user);

    function test_set_chain_to_claim_rewards() external init {
        vm.prank(alice);
        vm.warp(1000);
        vm.expectEmit();
        emit SetChainToClaimRewards(alice);
        referralRegistry.setChainToClaimRewards();
        assertEq(referralRegistry.chainToClaimSetTime(alice), 1000, "chain to claim should be set");
    }

    event EpochEnded(uint256 indexed epoch);
    function test_next_epoch() external init {
        vm.mockCall(twapOracle, abi.encodeWithSelector(IXENTwapOracle.lastTWAP.selector), abi.encode(7e12));

        assertEq(referralController.currentEpoch(), 24);

        vm.expectRevert("!enableNextEpoch");
        referralController.nextEpoch();

        vm.prank(owner);
        referralController.setEnableNextEpoch(true);
        vm.expectRevert("now < trigger time");
        referralController.nextEpoch();

        vm.warp(lastTimestamp + epochDuration);
        vm.expectEmit();
        emit EpochEnded(24);
        referralController.nextEpoch();

        (uint64 _startTime, uint64 _endTime,,) = referralController.epochs(referralController.currentEpoch());
        assertEq(_startTime, lastTimestamp + epochDuration);
        assertEq(_endTime, 0);

        //prev epoch
        (_startTime, _endTime,,) = referralController.epochs(referralController.currentEpoch() - 1);
        assertEq(_endTime, lastTimestamp + epochDuration);

        vm.warp(lastTimestamp + epochDuration * 2);
        referralController.nextEpoch();

        vm.warp(lastTimestamp + epochDuration * 3);
        referralController.nextEpoch();
    }

    function test_only_distributor_can_toggle_next_epoch() external init {
        vm.prank(alice);
        vm.expectRevert("!distributor");
        referralController.setEnableNextEpoch(false);

        vm.prank(owner);
        referralController.setEnableNextEpoch(false);
    }

    function test_set_epoch_duration() external init {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        referralController.setEpochDuration(epochDuration);

        vm.startPrank(owner);
        vm.expectRevert("_epochDuration < MIN_EPOCH_DURATION");
        referralController.setEpochDuration(epochDuration / 10);

        referralController.setEpochDuration(epochDuration);
    }

    function test_control_poolhook_and_update_fee() external init {
        vm.startPrank(dee);
        vm.expectRevert("Ownable: caller is not the owner");
        referralController.setPoolHook(dee);
        vm.expectRevert("!poolHook");
        referralController.updateFee(dee, 10e18);
        vm.stopPrank();

        vm.startPrank(owner);
        referralController.setPoolHook(dee);
        vm.stopPrank();

        vm.startPrank(dee);
        referralController.updateFee(address(0), 10e18);
        referralController.updateFee(alice, 10e18);
        referralController.updateFee(dee, 10e18);
        (,,, uint256 _totalFee) = referralController.epochs(referralController.currentEpoch());
        assertEq(referralController.users(referralController.currentEpoch(), alice), 10e18);
        assertEq(_totalFee, 20e18);
    }
}
