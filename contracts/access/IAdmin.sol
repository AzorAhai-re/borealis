// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

interface IAdmin {
    function pauseBonding() external;
    function unpauseBonding() external;

    function approveMint(address minter) external;
    function approveBurn(address burner) external;

    function isPaused() external returns (bool);
    function isMinter(address minter) external returns (bool);
    function isBurner(address burner) external returns (bool);
    function isBonder(address bonder) external returns (bool);
    function isGovernor(address govAddress) external returns (bool);

    function setGovernor(address governor) external;

    function revokeNonGovernor(bytes32 role, address account) external;

    function approveBonding(address bonder) external;
}