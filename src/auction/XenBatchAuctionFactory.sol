// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {XenBatchAuction} from "./XenBatchAuction.sol";
import {IAuctionTreasury} from "../interfaces/IAuctionTreasury.sol";

contract XenBatchAuctionFactory is Ownable2Step {
    using SafeERC20 for IERC20;

    uint64 public constant MIN_AUCTION_DURATION = 0.5 hours;
    uint64 public constant MAX_AUCTION_DURATION = 10 days;

    address public constant XEN = 0x6810AB468fFD38Accc787D0119dc20Ba1C9E554F;
    address public constant payToken = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    uint64 public vestingDuration;
    uint128 public minimumCeilingPrice;
    address public treasury;
    address public admin;
    address[] public auctions;

    constructor(address _treasury, address _admin, uint64 _vestingDuration, uint128 _minimumCeilingPrice) {
        minimumCeilingPrice = _minimumCeilingPrice;
        setTreasury(_treasury);
        setAdmin(_admin);
        setVestingDuration(_vestingDuration);
    }

    /*===================== VIEWS =====================*/
    function totalAuctions() public view returns (uint256) {
        return auctions.length;
    }

    function createAuction(
        uint128 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint128 _ceilingPrice,
        uint128 _minPrice
    ) external onlyOwner {
        require(_endTime - _startTime >= MIN_AUCTION_DURATION, "< MIN_AUCTION_DURATION");
        require(_endTime - _startTime <= MAX_AUCTION_DURATION, "> MAX_AUCTION_DURATION");
        require(_ceilingPrice >= minimumCeilingPrice, "ceilingPrice < minimum ceiling price");
        XenBatchAuction _newAuction = new XenBatchAuction(
            XEN,
            payToken,
            _totalTokens,
            _startTime,
            _endTime,
            minimumCeilingPrice,
            _ceilingPrice,
            _minPrice,
            admin,
            treasury,
            vestingDuration);

        IAuctionTreasury(treasury).transferXEN(address(_newAuction), _totalTokens);
        auctions.push(address(_newAuction));

        emit AuctionCreated(
            XEN,
            payToken,
            _totalTokens,
            _startTime,
            _endTime,
            _ceilingPrice,
            _minPrice,
            admin,
            treasury,
            address(_newAuction)
        );
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit AuctionTreasuryUpdated(_treasury);
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AuctionAdminUpdated(_admin);
    }

    function setVestingDuration(uint64 _vestingDuration) public onlyOwner {
        vestingDuration = _vestingDuration;
        emit VestingDurationSet(_vestingDuration);
    }

    function setMinimumCeilingPrice(uint128 _minimumCeilingPrice) public onlyOwner {
        require(_minimumCeilingPrice > 0, "Invalid value");
        minimumCeilingPrice = _minimumCeilingPrice;
        emit MinimumCeilingPriceSet(_minimumCeilingPrice);
    }

    // EVENTS
    event AuctionCreated(
        address indexed _auctionToken,
        address indexed _payToken,
        uint256 _totalTokens,
        uint64 _startTime,
        uint64 _endTime,
        uint256 _ceilingPrice,
        uint256 _minPrice,
        address _auctionAdmin,
        address _auctionTreasury,
        address _newAuction
    );
    event AuctionAdminUpdated(address indexed _address);
    event AuctionTreasuryUpdated(address indexed _address);
    event VestingDurationSet(uint64 _duration);
    event MinimumCeilingPriceSet(uint128 _minimumCeilingPrice);
}
