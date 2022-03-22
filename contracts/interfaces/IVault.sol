// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

interface IVault {
    function deposit(address account, uint256 amount) external;
    function withdraw(address account, uint256 amount) external;

    event Deposited(address indexed account, uint256 indexed amount);
    event Withdrawn(address indexed account, uint256 indexed amount);
}
