// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./BurnableOFTUpgradeable.sol";

contract XenaToken is BurnableOFTUpgradeable {
    address[] private _pools;
    uint256 private _totalBurned;

    /* ========== GOVERNANCE ========== */
    function addPool(address _newPool) external onlyOwner {
        _pools.push(_newPool);
        emit PoolAdded(_newPool);
    }

    function setPools(address[] memory _newPools) external onlyOwner {
        delete _pools;
        uint256 _length = _newPools.length;
        for (uint256 i = 0; i < _length; i++) {
            address _np = _newPools[i];
            _pools.push(_np);
            emit PoolAdded(_np);
        }
    }

    /* ========== VIEWS ========== */
    function circulatingSupply() public view virtual override returns (uint256 _cp) {
        unchecked {
            _cp = totalSupply();
            uint256 _length = _pools.length;
            for (uint256 i = 0; i < _length; i++) {
                _cp -= balanceOf(_pools[i]);
            }
        }
    }

    function pool(uint256 _index) external view virtual returns (address) {
        return _pools[_index];
    }

    function poolLength() external view virtual returns (uint256) {
        return _pools.length;
    }

    function totalBurned() external view returns (uint256) {
        return _totalBurned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function burn(uint256 _amount) external virtual override {
        burnFrom(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) public virtual override {
        _totalBurned += _amount;
        super.burnFrom(_account, _amount);
    }

    /* ========== EVENTS ========== */
    event PoolAdded(address indexed newPool);
}
