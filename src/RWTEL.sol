// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { AxelarGMPExecutable } from
    "@axelar-cgp-solidity/node_modules/@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarGMPExecutable.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RWTEL is RecoverableWrapper, AxelarGMPExecutable, UUPSUpgradeable, OwnableUpgradeable {
    /* RecoverableWrapper Storage Layout (Non-ERC7201 compliant)
     _______________________________________________________________________________________
    | Name              | Type                                                       | Slot |
    |-------------------|------------------------------------------------------------|------|
    | _balances         | mapping(address => uint256)                                | 0    |
    | _allowances       | mapping(address => mapping(address => uint256))            | 1    |
    | _totalSupply      | uint256                                                    | 2    |
    | _name             | string                                                     | 3    |
    | _symbol           | string                                                     | 4    |
    | _accountState     | mapping(address => struct RecoverableWrapper.AccountState) | 5    |
    | frozen            | mapping(address => uint256)                                | 6    |
    | _unsettledRecords | mapping(address => struct RecordsDeque)                    | 7    |
    | unwrapDisabled    | mapping(address => bool)                                   | 8    |
    | _totalSupply      | uint256                                                    | 9    |
    | governanceAddress | address                                                    | 10   |
    
    */

    /// @dev Overrides for `ERC20` storage since `RecoverableWrapper` dep restricts them
    string _name_;
    string _symbol_;

    struct ExtCall {
        address target;
        uint256 value;
        bytes data;
    }

    error ExecutionFailed(bytes32 commandId, address target);

    /// @notice For use when deployed as singleton
    /*
    constructor(
        address gateway_,
        string memory name_,
        string memory symbol_,
        uint256 recoverableWindow_,
        address governanceAddress_,
        address baseERC20_,
        uint16 maxToClean
    )
        AxelarGMPExecutable(gateway_)
        RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean)
    { }
    */

    /**
     *
     *   upgradeability
     *
     */

    /// @notice Replaces `constructor` for use when deployed as a proxy implementation
    /// @dev This function and all functions invoked within are only available on devnet and testnet
    function initialize(
        address gateway_,
        string memory name_,
        string memory symbol_,
        uint256 recoverableWindow_,
        address governanceAddress_,
        address baseERC20_,
        uint16 maxToClean,
        address owner
    )
        public
        initializer
    {
        __Ownable_init(owner);
        setGateway(gateway_);
        setName(name_);
        setSymbol(symbol_);
        setRecoverableWindow(recoverableWindow_);
        setGovernanceAddress(governanceAddress_);
        setBaseERC20(baseERC20_);
        setMaxToClean(maxToClean);
    }

    function setGateway(address gateway) public onlyOwner {
        gatewayAddress = gateway;
    }

    function setName(address newName) public onlyOwner {
        _name_ = name;
    }

    function setSymbol(address newSymbol) public onlyOwner {
        _symbol_ = symbol;
    }

    function setRecoverableWindow(address newRecoverableWindow) public onlyOwner {
        recoverableWindow = newRecoverableWindow;
    }

    function setGovernanceAddress(address newGovernanceAddress) public onlyOwner {
        governanceAddress = newGovernanceAddress;
    }

    function setBaseERC20(address newBaseERC20) public onlyOwner {
        baseERC20 = IERC20Metadata(newBaseERC20);
    }

    function setMaxToClean(address maxToClean) public onlyOwner {
        MAX_TO_CLEAN = maxToClean;
    }

    function name() public view virtual override returns (string memory) {
        return _name_;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol_;
    }

    /**
     *
     *   internals
     *
     */

    /// @notice Only invoked after `commandId` is verified by Axelar gateway, ie in the context of an incoming message
    /// @notice Params `sourceChain` and `sourceAddress` are not currently used for vanilla bridging but may later on
    function _execute(
        bytes32 commandId,
        string calldata, /* sourceChain */
        string calldata, /* sourceAddress */
        bytes calldata payload
    )
        internal
        virtual
        override
    {
        ExtCall memory bridgeMsg = abi.decode(payload, (ExtCall));
        address target = bridgeMsg.target;
        (bool res,) = target.call{ value: bridgeMsg.value }(bridgeMsg.data);
        if (!res) revert ExecutionFailed(commandId, target);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
