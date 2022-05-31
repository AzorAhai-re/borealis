// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "./IManager.sol";

interface IMap {

    function token() external view returns(IToken);
}
