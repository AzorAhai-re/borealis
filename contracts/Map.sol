// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "./interfaces/IMap.sol";
import "./access/IAdmin.sol";

contract Map is IMap {
    IManager private _manager;
    IToken private _token;

    constructor(address manager) {
        _manager = IManager(manager);
        _token = IManager(manager).token();
    }

    function token() public override view returns(IToken) {
        return _token;
    }

    function curve() public override view returns(IBondingCurve _curve) {
        _curve = _manager.curve();
        require(address(_curve) != address(0), "Map: curve not yet set");
    }

    function updateToken() internal returns (bool hasUpdated){
        IToken currToken = _manager.token();
        if (address(currToken) != address(_token)){
            _token = currToken;
            hasUpdated = true;
        }
        else {
            hasUpdated = false;
        }
    }

    function setManager(address newManager) external override {
        require(
            IAdmin(address(_manager)).isGovernor(msg.sender),
            "Map: only the governor can set the manager"
        );
        _setManager(IManager(newManager));
    }

    function _setManager(IManager newManager) private {
        _manager = newManager;
    }
}
