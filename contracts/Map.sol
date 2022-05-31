// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "./interfaces/IMap.sol";

contract Map is IMap {
    IManager private immutable _manager;
    IToken private immutable _token;

    uint256 private rateLimitEpoch;
    uint256 private rateLimitThreshold;

    constructor(address manager) {
        _manager = IManager(manager);

        _token = IManager(manager).token();
    }


    function token() public override view returns(IToken) {
        return _token;
    }

    function _setRateLimitEpoch(uint256 _newLimit) internal {
        rateLimitEpoch = _newLimit;
    }

    function _setRateLimitThreshold(uint256 _newThreshold) internal {
        rateLimitThreshold = _newThreshold;
    }
}
