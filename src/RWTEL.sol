// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { InterchainTokenExecutable } from
    "@axelar-network/interchain-token-service/contracts/executable/InterchainTokenExecutable.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { IRWTEL, ExtCall } from "./interfaces/IRWTEL.sol";

import { Test, console2 } from "forge-std/Test.sol"; //todo

/* RecoverableWrapper Storage Layout (Provided because RW is non-ERC7201 compliant)
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

contract RWTEL is IRWTEL, RecoverableWrapper, InterchainTokenExecutable, UUPSUpgradeable, Ownable {
    /// @dev ConsensusRegistry system contract defined by protocol to always exist at a constant address
    address public constant consensusRegistry = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1;

    /// @dev Overrides for `ERC20` storage since `RecoverableWrapper` dep restricts them
    string internal constant _name_ = "Recoverable Wrapped Telcoin";
    string internal constant _symbol_ = "rwTEL";

    /// @dev Required by `RecoverableWrapper` and `AxelarGMPExecutable` deps to write immutable vars to bytecode
    /// @param name_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    /// @param symbol_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    constructor(
        address interchainTokenService_,
        string memory name_,
        string memory symbol_,
        uint256 recoverableWindow_,
        address governanceAddress_,
        address baseERC20_,
        uint16 maxToClean
    )
        InterchainTokenExecutable(interchainTokenService_)
        RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean)
    { }

    //todo: delete
    /// @note: incoming flow: bridgeMsg => mint(user, nativeTELAmt)
    /// @todo: mint logic for tokenmanager caller
    /// @notice Invoked by ITS within `TokenHandler::giveToken()`
    // function mint(address to, uint256 amount) external {
    // todo: must send *native* TEL, not rwTEL (burn is opposite)
    // todo: rwTEL <> native TEL ledger *must* remain intact
    //}
    /// @note: exit flow: user => this.deposit(nativeTEL) => waitSettleBal(rw) => its.interchainTransfer()
    /// @todo: burn logic for tokenmanager caller
    /// @notice Invoked by ITS within `TokenHandler::takeToken()`
    // function burn(address from, uint256 amount) external {
    // todo: must restrict burns to settled balances of rwTEL only
    // todo: rwTEL <> native TEL ledger *must* remain intact
    //}


    /// @inheritdoc IRWTEL
    function distributeStakeReward(address validator, uint256 rewardAmount) external {
        if (msg.sender != consensusRegistry) revert OnlyConsensusRegistry();

        (bool res,) = validator.call{ value: rewardAmount }("");
        if (!res) revert RewardDistributionFailure(validator);
    }

    /**
     *
     *   upgradeability
     *
     */

    /// @inheritdoc IRWTEL
    function initialize(address governanceAddress_, uint16 maxToClean_, address owner_) public initializer {
        _initializeOwner(owner_);
        _setGovernanceAddress(governanceAddress_);
        _setMaxToClean(maxToClean_);
    }

    /// @inheritdoc IRWTEL
    function setGovernanceAddress(address newGovernanceAddress) public override onlyOwner {
        _setGovernanceAddress(newGovernanceAddress);
    }

    /// @inheritdoc IRWTEL
    function setMaxToClean(uint16 newMaxToClean) public override onlyOwner {
        _setMaxToClean(newMaxToClean);
    }

    /// @notice Overrides `RecoverableWrapper::ERC20::name()` which accesses a private var
    function name() public view virtual override returns (string memory) {
        return _name_;
    }

    /// @notice Overrides `RecoverableWrapper::ERC20::name()` which accesses a private var
    function symbol() public view virtual override returns (string memory) {
        return _symbol_;
    }

    /// @notice Used to burn TEL when bridging off of TN; can be reminted only through valid bridge tx
    receive() external payable { }

    /**
     *
     *   internals
     *
     */

    //todo: override safeTransfer, transfer, transferFrom too?
    /// @notice Overridden because RWTEL TokenManager bridging (`LOCK_UNLOCK`) uses `safeTransferFrom`
    function safetransferfrom(address from, address to, uint256 amount) external override returns (bool) {
        // custom override logic for Axelar interchain GMP messages
        if (msg.sender == interchainTokenService) {
            if (from == tokenManager && to == address(this)) {
              // incoming bridge tx initiated by `ITS::execute()`
              // do nothing bc execute flow will be invoked which "mints" native TEL to user
              return true;
            } else if (to == tokenManager) {
              // exit bridge tx initiated by`ITS::interchainTransfer()` or `ITS::transmitInterchainTransfer()`
              // note: execute flow will *not* be invoked because `from == user` thus rwTEL must be burned from user
              _burnFrom(user, amount); // burn rwTEL

              // todo: make sure (settledBalanceOf(user) >= amount)
              // todo: make sure ledger of rwTEL vs TEL vs ethTEL is intact
              // note: native TEL would already have been "burned" when user minted rwTEL via deposit() 
              return true;
            }
        }

        // todo: what to do about a transfer where from == anyUser && to == tokenManager?

        super.safeTransferFrom(from, to, amount);
    }

    /// @notice Only invoked after incoming message is verified by InterchainTokenService and `Gateway::validateContractCall()`
    /// @notice Params `sourceChain` and `sourceAddress` are not currently used for vanilla bridging but may later on
    function _executeWithInterchainToken(
        bytes32 commandId,
        string calldata, /* sourceChain */
        bytes calldata, /* sourceAddress */
        bytes calldata data,
        bytes32 tokenId,
        address token,
        uint256 amount
    )
        internal
        virtual
        override
    {
        // todo: revisit ExtCall payload
        // todo: should require `messageType = INTERCHAIN_TRANSFER || SEND_TO_HUB || RECEIVE_FROM_HUB`
        // todo: should RWTEL inherit InterchainTokenStandard instead of InterchainTokenExecutable? only if it can be linked to ethTEL
        ExtCall memory bridgeMsg = abi.decode(data, (ExtCall));
        address target = bridgeMsg.target;
        if (token != address(address(this))) {
            // ITS handles logic for supporting all other ERC20s, so reaching this branch means destination address was specified as rwTEL
            // todo: revert InvalidToken(commandId, token);
            revert();
        }
        if (target == address(this)) {
            //todo: revert InvalidTarget(commandId, target);
            revert();
        } 
        // todo: is ExtCall.value still required when amount is provided?
        if (amount != bridgeMsg.value) {
            //todo: revert InvalidAmount(commandId, amount, bridgeMsg.value);
            revert();
        }

        // todo: ensure reentrancy (ie handler.giveToken) is not possible
        (bool res,) = target.call{ value: bridgeMsg.value }(bridgeMsg.data);
        // to prevent stuck messages, emit failure event rather than revert
        if (!res) emit ExecutionFailed(commandId, target);
    }

    function _setGovernanceAddress(address newGovernanceAddress) internal {
        governanceAddress = newGovernanceAddress;
    }

    function _setMaxToClean(uint16 newMaxToClean) internal {
        assembly {
            sstore(11, newMaxToClean)
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
