// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { IInterchainTokenStandard } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenStandard.sol";
import { ITransmitInterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interfaces/ITransmitInterchainToken.sol";
import { IInterchainTokenFactory } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenFactory.sol";
import { IInterchainTokenService } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenService.sol";
import { InterchainTokenStandard } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainTokenStandard.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { RecordsDeque, RecordsDequeLib, Record } from "recoverable-wrapper/contracts/util/RecordUtil.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeCast } from "@openzeppelin-contracts/utils/math/SafeCast.sol";
import { ERC20 } from "node_modules/recoverable-wrapper/node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { WETH } from "solady/tokens/WETH.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { SystemCallable } from "./consensus/SystemCallable.sol";
import { IRWTEL } from "./interfaces/IRWTEL.sol";

/// @title Recoverable Wrapped Telcoin
/// @notice The RWTEL module serves as an Axelar InterchainToken merging functionality of TEL
/// both as ITS ERC20 token and as native gas currency for TN
/// @dev Inbound ERC20 TEL from other networks is delivered as native TEL through custom mint logic
/// whereas outbound native TEL must first be double-wrapped, with `wTEL::deposit()` and then `rwTEL::wrap()`
/// For security, only RWTEL balances settled by elapsing the recoverable window can be bridged
contract RWTEL is IRWTEL, RecoverableWrapper, InterchainTokenStandard, UUPSUpgradeable, Ownable, SystemCallable {
    using RecordsDequeLib for RecordsDeque;

    /// @dev StakeManager system precompile assigned by protocol to a constant address
    address public constant stakeManager = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1;

    /// @dev The precompiled Axelar ITS TokenManager contract address for this token
    address public immutable tokenManager;
    /// @dev The precompiled Axelar ITS contract address for this chain
    address private immutable _interchainTokenService;

    /// @dev Constants for deriving the origin chain's ITS custom linked deploy salt, token id, and TokenManager address
    address private immutable originTEL;
    address private immutable originLinker;
    bytes32 private immutable originSalt;
    bytes32 private immutable originChainNameHash;
    bytes32 private constant PREFIX_CUSTOM_TOKEN_SALT = keccak256("custom-token-salt");
    bytes32 private constant PREFIX_INTERCHAIN_TOKEN_ID = keccak256("its-interchain-token-id");
    bytes32 private constant CREATE_DEPLOY_BYTECODE_HASH =
        0xdb4bab1640a2602c9f66f33765d12be4af115accf74b24515702961e82a71327;
    /// @notice Token factory flag to be create3-agnostic; see `InterchainTokenService::TOKEN_FACTORY_DEPLOYER`
    address private constant TOKEN_FACTORY_DEPLOYER = address(0x0);

    /// @dev Overrides for `ERC20` storage since `RecoverableWrapper` dep restricts them
    string internal constant _name_ = "Recoverable Wrapped Telcoin";
    string internal constant _symbol_ = "rwTEL";

    uint256 public constant DECIMALS_CONVERTER = 1e16;

    modifier onlyTokenManager() {
        if (msg.sender != tokenManager) revert OnlyManager(tokenManager);
        _;
    }

    modifier onlyStakeManager() {
        if (msg.sender != stakeManager) revert OnlyManager(stakeManager);
        _;
    }

    /// @dev Required by `RecoverableWrapper` and `AxelarGMPExecutable` deps to write immutable vars to bytecode
    /// @param name_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    /// @param symbol_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    constructor(
        address originTEL_,
        address originLinker_,
        bytes32 originSalt_,
        string memory originChainName_,
        address interchainTokenService_,
        string memory name_,
        string memory symbol_,
        uint256 recoverableWindow_,
        address governanceAddress_,
        address baseERC20_,
        uint16 maxToClean
    )
        RecoverableWrapper(name_, symbol_, recoverableWindow_, governanceAddress_, baseERC20_, maxToClean)
    {
        _disableInitializers();
        _interchainTokenService = interchainTokenService_;
        originTEL = originTEL_;
        originLinker = originLinker_;
        originSalt = originSalt_;
        originChainNameHash = keccak256(bytes(originChainName_));
        tokenManager = tokenManagerAddress();
    }

    /**
     *
     *   RWTEL Core
     *
     */

    /// @inheritdoc IRWTEL
    function distributeStakeReward(address validator, uint256 rewardAmount) external virtual onlyStakeManager {
        (bool res,) = validator.call{ value: rewardAmount }("");
        if (!res) revert RewardDistributionFailure(validator);
    }

    /// @inheritdoc IRWTEL
    function doubleWrap() external payable virtual {
        address caller = msg.sender;
        uint256 amount = msg.value;
        if (amount == 0) revert MintFailed(caller, amount);

        WETH wTEL = WETH(payable(address(baseERC20)));
        wTEL.deposit{ value: amount }();

        _mint(caller, amount);
        emit Wrap(caller, amount);
    }

    /// @inheritdoc IRWTEL
    function permitWrap(
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        payable
        virtual
    {
        if (amount == 0) revert MintFailed(owner, amount);

        WETH wTEL = WETH(payable(address(baseERC20)));
        wTEL.permit(owner, address(this), amount, deadline, v, r, s);

        bool success = wTEL.transferFrom(owner, address(this), amount);
        if (!success) revert PermitWrapFailed(owner, amount);

        _mint(owner, amount);
        emit Wrap(owner, amount);
    }

    /// @notice Named by inheritance: has no relationship to `mint()`
    function _mint(address account, uint256 amount) internal virtual override {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        _clean(account);

        // 10e12 TEL supply can never overflow w/out inflating 27 orders of magnitude
        uint128 bytes16Amount = SafeCast.toUint128(amount);
        _unsettledRecords[account].enqueue(bytes16Amount, block.timestamp + recoverableWindow);

        _totalSupply += amount;
        _accountState[account].nonce++;
        _accountState[account].balance += bytes16Amount;
    }

    /// @inheritdoc IRWTEL
    function unsettledRecords(address account) public view returns (Record[] memory) {
        RecordsDeque storage rd = _unsettledRecords[account];
        if (rd.isEmpty()) return new Record[](0);

        Record[] memory temp = new Record[](rd.tail - rd.head + 1);
        uint256 count = 0;

        uint256 currentIndex = rd.tail;
        while (currentIndex != 0) {
            Record storage currentRecord = rd.queue[currentIndex];

            if (currentRecord.settlementTime > block.timestamp) {
                temp[count] = currentRecord;
                count++;
            }

            currentIndex = currentRecord.prev;
        }

        Record[] memory unsettled = new Record[](count);
        for (uint256 i = 0; i < count; ++i) {
            unsettled[i] = temp[i];
        }

        return unsettled;
    }

    /// @notice Overrides `RecoverableWrapper::ERC20::name()` which accesses a private var
    function name() public view virtual override returns (string memory) {
        return _name_;
    }

    /// @notice Overrides `RecoverableWrapper::ERC20::name()` which accesses a private var
    function symbol() public view virtual override returns (string memory) {
        return _symbol_;
    }

    /**
     *
     *   Axelar Interchain Token Service
     *
     */

    /// @inheritdoc IRWTEL
    function mint(address to, uint256 interchainAmount) external virtual override onlyTokenManager returns (uint256) {
        uint256 nativeAmount = toEighteenDecimals(interchainAmount);

        (bool r,) = to.call{ value: nativeAmount }("");
        if (!r) revert MintFailed(to, nativeAmount);

        return nativeAmount;
    }

    /// @inheritdoc IRWTEL
    function burn(address from, uint256 nativeAmount) external virtual override onlyTokenManager returns (uint256) {
        // burn from settled balance only
        _burn(from, nativeAmount);
        // reclaim native TEL to maintain integrity of rwTEL <> wTEL <> TEL ledgers
        WETH(payable(address(baseERC20))).withdraw(nativeAmount);

        (uint256 interchainAmount, uint256 remainder) = toTwoDecimals(nativeAmount);

        // do not revert bridging if forwarding truncated unbridgeable amount fails
        (bool r,) = governanceAddress.call{ value: remainder }("");
        if (!r) emit RemainderTransferFailed(from, remainder);

        return interchainAmount;
    }

    /// @inheritdoc IRWTEL
    function isMinter(address addr) external view virtual returns (bool) {
        if (addr == tokenManagerAddress()) return true;

        return false;
    }

    /// @inheritdoc IRWTEL
    function toEighteenDecimals(uint256 interchainAmount) public pure returns (uint256) {
        uint256 nativeAmount = interchainAmount * DECIMALS_CONVERTER;
        return nativeAmount;
    }

    /// @inheritdoc IRWTEL
    function toTwoDecimals(uint256 nativeAmount) public pure returns (uint256, uint256) {
        if (nativeAmount < DECIMALS_CONVERTER) revert InvalidAmount(nativeAmount);
        uint256 interchainAmount = nativeAmount / DECIMALS_CONVERTER;
        uint256 remainder = nativeAmount % DECIMALS_CONVERTER;

        return (interchainAmount, remainder);
    }

    /// @inheritdoc IRWTEL
    function tokenManagerCreate3Salt() public view override returns (bytes32) {
        return interchainTokenId();
    }

    /// @notice Returns the top-level ITS interchain token ID for RWTEL
    /// @dev The interchain token ID is *custom-linked*, ie based on Ethereum ERC20 TEL, and shared across chains
    function interchainTokenId() public view override returns (bytes32) {
        return keccak256(abi.encode(PREFIX_INTERCHAIN_TOKEN_ID, TOKEN_FACTORY_DEPLOYER, linkedTokenDeploySalt()));
    }

    /// @inheritdoc IRWTEL
    function linkedTokenDeploySalt() public view override returns (bytes32) {
        return keccak256(abi.encode(PREFIX_CUSTOM_TOKEN_SALT, originChainNameHash, originLinker, originSalt));
    }

    /// @inheritdoc IRWTEL
    function tokenManagerAddress() public view override returns (address) {
        address createDeploy = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", interchainTokenService(), tokenManagerCreate3Salt(), CREATE_DEPLOY_BYTECODE_HASH
                        )
                    )
                )
            )
        );

        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", createDeploy, hex"01")))));
    }

    /// @inheritdoc InterchainTokenStandard
    function interchainTokenService() public view virtual override returns (address) {
        return _interchainTokenService;
    }

    function _spendAllowance(
        address sender,
        address spender,
        uint256 amount
    )
        internal
        virtual
        override(ERC20, InterchainTokenStandard)
    {
        ERC20._spendAllowance(sender, spender, amount);
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

    receive() external payable {
        address wTEL = address(baseERC20);
        if (msg.sender != wTEL) revert OnlyBaseToken(wTEL);
    }
}
