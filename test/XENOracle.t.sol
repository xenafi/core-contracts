pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "src/oracle/XENTwapOracle.sol";

contract TestOracle is Test {
    address _owner;
    address constant XEN_USDT_PAIR_ADDR = 0xc11cFF8A44853A5B3F24a7F4B817E6e64fbEBA2a;
    address constant XEN_ADDR = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;
    XENTwapOracle xenOracle;

    function setUp() external {
        _owner = msg.sender;
        vm.createSelectFork("https://rpc.ankr.com/arbitrum");
        xenOracle = new XENTwapOracle(XEN_ADDR, XEN_USDT_PAIR_ADDR, _owner);
        vm.prank(_owner);
        xenOracle.update();
        vm.warp(block.timestamp + 86400);
    }

    function test_get_current_twap() external {
        uint256 _currentTWAP = xenOracle.getCurrentTWAP();
        assertTrue(_currentTWAP > 0);
        console.log(_currentTWAP);
    }

    function test_update_twap() external {
        vm.prank(_owner);
        xenOracle.update();
        assertTrue(xenOracle.lastTWAP() > 0);
        console.log(xenOracle.lastTWAP());
    }
}
