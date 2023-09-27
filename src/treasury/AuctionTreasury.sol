// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @notice hold XEN token to used in auction and receive token commited by user when auction success
 *  The pay token then converted to protocol owned LP
 */
contract AuctionTreasury is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO_PRECISION = 1000;

    IERC20 public constant XEN = IERC20(0x6810AB468fFD38Accc787D0119dc20Ba1C9E554F);
    IERC20 public constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    /// @notice XENAuctionFactory can request transfer protocol tokens from this contract
    address public XENAuctionFactory;
    /// @notice address allowed to call distribute bid token
    address public admin;
    /// @notice hold USDT to be converted to XEN/USDT LP
    address public cashTreasury;
    /// @notice hold USDT to deposit to Pool and become LLP
    address public llpReserve;
    /// @notice part of token to be sent to treasury to convert to XEN/USDT LP
    uint256 public usdtToCashTreasuryRatio;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _cashTreasury, address _llpReserve) external initializer {
        __Ownable_init();
        require(_cashTreasury != address(0), "Invalid address");
        require(_llpReserve != address(0), "Invalid address");
        cashTreasury = _cashTreasury;
        llpReserve = _llpReserve;
        usdtToCashTreasuryRatio = 750;
    }

    /**
     * @notice request by authorized auction contract factory when creating a new auction
     */
    function transferXEN(address _for, uint256 _amount) external {
        require(msg.sender == XENAuctionFactory, "only XENAuctionFactory");
        XEN.safeTransfer(_for, _amount);
        emit XENGranted(_for, _amount);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setXENAuctionFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid address");
        XENAuctionFactory = _factory;
        emit XENAuctionFactorySet(_factory);
    }

    /**
     * @notice distribute USDT to each reserves
     */
    function distribute() external {
        require(msg.sender == admin || msg.sender == owner(), "Only Owner or Admin can operate");
        uint256 _usdtBalance = USDT.balanceOf(address(this));
        uint256 _amountToTreasury = (_usdtBalance * usdtToCashTreasuryRatio) / RATIO_PRECISION;
        uint256 _amountToLP = _usdtBalance - _amountToTreasury;

        // 1. split to Treasury
        if (_amountToTreasury > 0) {
            require(cashTreasury != address(0), "Invalid address");
            USDT.safeTransfer(cashTreasury, _amountToTreasury);
        }

        // 2. convert to LP
        if (_amountToLP > 0) {
            require(llpReserve != address(0), "Invalid address");
            USDT.safeTransfer(llpReserve, _amountToLP);
        }
    }

    function recoverFund(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    /* ========== EVENTS ========== */
    event AdminSet(address _admin);
    event XENGranted(address _for, uint256 _amount);
    event LGOGranted(address _for, uint256 _amount);
    event XENAuctionFactorySet(address _factory);
    event LGOAuctionFactorySet(address _factory);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
    event FundWithdrawn(address indexed _token, address _to, uint256 _amount);
}
