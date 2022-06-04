// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./IAdmin.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract Admin is AccessControl, IAdmin, Pausable {

    // TOKEN ROLES
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // MANAGER
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // BONDING CURVE
    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");

    modifier noFunnyBusiness (address _assignee) {
        require(_assignee != address(0), "Admin: Zero Address given");
        _;
    }

    modifier alreadyHasRole (bytes32 _role, address _assignee) {
        require(! hasRole(_role, _assignee), "Admin: assignee already has role");
        _;
    }

    constructor() {
        _setGovernor(msg.sender);

        _setRoleAdmin(MINTER_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(BURNER_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(GOVERNOR_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(UNBOND_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(BOND_ROLE, GOVERNOR_ROLE);
    }

    function approveMint(address minter) public override
        whenNotPaused
        onlyRole(GOVERNOR_ROLE)
    {
        _approveMint(minter);
    }
    
    function approveBurn(address burner) public override
        whenNotPaused
        onlyRole(GOVERNOR_ROLE)
    {
        _approveBurn(burner);
    }

    function setGovernor(address governor) public override
        whenNotPaused
        onlyRole(GOVERNOR_ROLE)
    {
        _setGovernor(governor);
    }

    function approveBonding(address bonder) public override whenNotPaused {
        _approveBonding(bonder);
    }

    function _revokeNonGovernor(bytes32 role, address account) internal {
        require(role != GOVERNOR_ROLE, "Admin: can not revoke governor");

        revokeRole(role, account);
    }

    function revokeNonGovernor(bytes32 role, address account) external override {
        _revokeNonGovernor(role, account);
    }

    function isPaused() public view override returns (bool) {
        return paused();
    }

    function isMinter(address minter) public view override returns (bool) {
        return hasRole(MINTER_ROLE, minter);
    }

    function isBurner(address burner) public view override returns (bool) {
        return hasRole(BURNER_ROLE, burner);
    }

    function isGovernor(address govAddress) public view override returns (bool){
        return hasRole(GOVERNOR_ROLE, govAddress);
    }

    function isBonder(address bonder) public view override returns (bool) {
        return hasRole(BOND_ROLE, bonder);
    }

    function _approveMint(address minter) internal
        noFunnyBusiness(minter)
        alreadyHasRole(MINTER_ROLE, minter)
    {
        _setupRole(MINTER_ROLE, minter);
    }

    function _approveBurn(address burner) internal
        noFunnyBusiness(burner)
        alreadyHasRole(BURNER_ROLE, burner)
    {
        _setupRole(BURNER_ROLE, burner);
    }

    function _setGovernor(address governor) internal
        noFunnyBusiness(governor)
        alreadyHasRole(GOVERNOR_ROLE, governor)
    {
        _setupRole(GOVERNOR_ROLE, governor);
    }

    function _approveBonding(address bonder) internal
        noFunnyBusiness(bonder)
        alreadyHasRole(BOND_ROLE, bonder)
    {
        _setupRole(BOND_ROLE, bonder);
    }

    function pauseBonding() public override onlyRole(GOVERNOR_ROLE){
        if (! paused()) _pause();
    }

    function unpauseBonding() public override onlyRole(GOVERNOR_ROLE){
        if (paused()) _unpause();
    }
}
