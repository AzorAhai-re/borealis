// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./access/IAdmin.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IManager.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract Token is IToken, ERC20 {
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public DOMAIN_SEPARATOR;

    // keccak256("Permit(
    //    address owner,address spender,uint256 value,
    //    uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    IManager internal _manager;
    mapping(address => uint256) public nonces;

    struct Permit {
        uint256 nonce;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    modifier onlyAuthed(address from, address to, uint256 amount, Permit memory permit_resp){
        require(block.timestamp <= permit_resp.deadline, "{token_name}: Trasnfer expired");
        require(permit_resp.nonce == nonces[from]++, "{token_name}: Nonce Invalid");
        bytes32 _digest = digest(from, to, amount, permit_resp.nonce, permit_resp.deadline);
        address recoveredAddress = ecrecover(_digest, permit_resp.v, permit_resp.r, permit_resp.s);
        require(
            recoveredAddress != address(0) && recoveredAddress == from,
            "{token_name}: INVALID_SIGNATURE"
        );
        _;
    }

    constructor (address manager)
        ERC20("{token_name}", "{token_symbol}")
    {
        uint256 chainId;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name())),
                keccak256(bytes(Strings.toString(1))),
                chainId,
                address(this)
            )
        );

        _manager = IManager(manager);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function digest(
        address from, address to, uint amount,
        uint nonce, uint deadline
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        from,
                        to,
                        amount,
                        nonce,
                        deadline
                    )
                )
            )
        );
    }

    /// @notice Mint `amount` {token_name}s `to` an address 
    /// @param to address to mint {token_name}s to
    /// @param amount how much {token_name}s to mint
    function mint(address to, uint256 amount) external override {
        require(IAdmin(address(_manager)).isMinter(msg.sender), "Token: Not authorized to mint");
        _mint(to, amount);
    }

    /// @notice Burn `amount` {token_name}s `to` an address 
    /// @param from address to burn {token_name}s from
    /// @param amount how much {token_name}s to burn
    function burn(address from, uint256 amount) external {
        require(IAdmin(address(_manager)).isBurner(msg.sender), "Token: Not authorized to burn");
        _burn(from, amount);
    }

    /// @notice transfer funds given a valid signature
    /// @dev Transfers tokens `from` one account `to` another provided
    /// that `to` has permision to send tokens on `from`'s behalf
    /// @param from owner of the tokens to be transfered
    /// @param to the receipient of the tokens
    /// @param amount how much tokens to be transfered
    /// @param permit_resp permit payload
    function tranferFromUsingPermit(
        address from,
        address to,
        uint256 amount,
        Permit memory permit_resp
    ) public onlyAuthed(from, to, amount, permit_resp) returns(bool) {
        _transfer(from, to, amount);
        return true;
    }

    /// @notice permit spending of {token_name}
    /// @param owner the {token_name} holder
    /// @param spender the approved operator
    /// @param value the amount approved
    /// @param deadline the deadline after which the approval is no longer valid
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "{token_name}: EXPIRED");
        bytes32 _digest = digest(owner, spender, value, nonces[owner]++, deadline);
        address recoveredAddress = ecrecover(_digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "{token_name}: INVALID_SIGNATURE"
        );
        _approve(owner, spender, value);
    }
}