// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { IInterchainTokenStandard } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenStandard.sol";
import { ITransmitInterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interfaces/ITransmitInterchainToken.sol";
import { IInterchainTokenService } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenService.sol";
import { InterchainTokenExecutable } from
    "@axelar-network/interchain-token-service/contracts/executable/InterchainTokenExecutable.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { SystemCallable } from "./consensus/SystemCallable.sol";
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

/// @title Recoverable Wrapped Telcoin
/// @notice The RWTEL module serves both as an Axelar ITS linked token and as InterchainExecutable
/// to merge functionality of TEL as an ITS-compatible ERC20 token and native gas currency for TN
/// @dev Inbound ERC20 TEL from other networks is delivered as native TEL through custom executable logic
/// whereas outbound TEL must first be double-wrapped from native TEL through wTEL to rwTEL.
/// For security, only RecoverableWrapper balances settled by the recoverable window can be bridged
contract RWTEL is IRWTEL, RecoverableWrapper, IInterchainTokenStandard, InterchainTokenExecutable, UUPSUpgradeable, Ownable, SystemCallable {
    address public constant ethereumTEL = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
    /// @dev ConsensusRegistry system contract defined by protocol to always exist at a constant address
    address public constant consensusRegistry = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1;

    /// @dev The Axelar ITS TokenManager contract address for this contract
    /// @notice Derived deterministically via CREATE3 and so will not contain code at genesis
    address public immutable tokenManager;

    /// @dev Constants for deriving this contract's canonical ITS deploy salt
    bytes32 public constant RWTEL_SALT = keccak256('recoverable-wrapped-telcoin');
    bytes32 private constant PREFIX_CANONICAL_TOKEN_SALT = keccak256('canonical-token-salt');

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
    { 
        _disableInitializers();
        tokenManager = _deriveTokenManager();
    }

    /// @inheritdoc IRWTEL
    function distributeStakeReward(address validator, uint256 rewardAmount) external {
        if (msg.sender != consensusRegistry) revert OnlyConsensusRegistry();

        (bool res,) = validator.call{ value: rewardAmount }("");
        if (!res) revert RewardDistributionFailure(validator);
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
     *   Axelar Interchain Token Service
     *
     */

    /// @inheritdoc IInterchainTokenStandard
    function interchainTransfer(
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) external payable {
        address sender = msg.sender;

        ITransmitInterchainToken(interchainTokenService).transmitInterchainTransfer{ value: msg.value }(
            canonicalInterchainTokenId(),
            sender,
            destinationChain,
            recipient,
            amount,
            metadata
        );
    }

    /// @inheritdoc IInterchainTokenStandard
    function interchainTransferFrom(
        address sender,
        string calldata destinationChain,
        bytes calldata recipient,
        uint256 amount,
        bytes calldata metadata
    ) external payable {
        _spendAllowance(sender, msg.sender, amount);

        ITransmitInterchainToken(interchainTokenService).transmitInterchainTransfer{ value: msg.value }(
            canonicalInterchainTokenId(),
            sender,
            destinationChain,
            recipient,
            amount,
            metadata
        );
    }

    //todo: override safeTransfer, transfer, transferFrom too?
    /// @inheritdoc IRWTEL
    function safetransferfrom(address from, address to, uint256 amount) external returns (bool) {
        // custom override logic for Axelar interchain GMP messages
        if (msg.sender == interchainTokenService) {
            if (from == tokenManager && to == address(this)) {
                // incoming bridge tx initiated by `ITS::execute()`
                // do nothing bc execute flow will be invoked which "mints" native TEL to user
                return true;
            } else if (to == tokenManager) {
                // exit bridge tx initiated by`ITS::interchainTransfer()` or `ITS::transmitInterchainTransfer()`
                // note: execute flow will *not* be invoked because `from == user` thus rwTEL must be burned from user
                _burn(from, amount);

                // todo: make sure (settledBalanceOf(user) >= amount)
                // todo: make sure ledger of rwTEL vs TEL vs ethTEL is intact
                // note: native TEL would already have been "burned" when user minted rwTEL via deposit()
                return true;
            }
        }

        // todo: what to do about a transfer where from == anyUser && to == tokenManager?

        // `RecoverableWrapper::transferFrom()` restricts transfers to settled balances
        super.transferFrom(from, to, amount);
        return true;
    }

    /// @inheritdoc IRWTEL
    function canonicalInterchainTokenId() public view override returns (bytes32) {
        return IInterchainTokenService(interchainTokenService).interchainTokenId(address(0x0), canonicalInterchainTokenDeploySalt());
    }

    /// @inheritdoc IRWTEL
    function canonicalInterchainTokenDeploySalt() public view override returns (bytes32) {
        bytes32 chainNameHash = IInterchainTokenService(interchainTokenService).chainNameHash();
        return keccak256(abi.encode(PREFIX_CANONICAL_TOKEN_SALT, chainNameHash, ethereumTEL));
    }

    /// @notice Only invoked for incoming TEL, is verified by InterchainTokenService and
    /// `Gateway::validateContractCall()`
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
        // ITS handles all other ERC20s; reaching this branch means destination address was specified as rwTEL
        if (token != address(this) || tokenId != canonicalInterchainTokenId()) revert InvalidToken(commandId, token, tokenId);

        // todo: should require `messageType = INTERCHAIN_TRANSFER || SEND_TO_HUB || RECEIVE_FROM_HUB`
        // todo: should RWTEL inherit InterchainTokenStandard instead of InterchainTokenExecutable? only if it can be
        // linked to ethTEL
        ExtCall memory bridgeMsg = abi.decode(data, (ExtCall));
        address target = bridgeMsg.target;
        if (target == address(this)) revert InvalidTarget(commandId, target);
        // todo: is ExtCall.value still required when amount is provided?
        if (amount != bridgeMsg.value) revert InvalidAmount(commandId, amount, bridgeMsg.value);

        // todo: ensure reentrancy (ie handler.giveToken) is not possible
        (bool res,) = target.call{ value: bridgeMsg.value }(bridgeMsg.data);
        if (!res) revert ExecutionFailed(commandId, target);
    }

    function _deriveTokenManager() internal pure returns (address) {
        //todo should this also derive tokenId or store it in bytecode?
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
