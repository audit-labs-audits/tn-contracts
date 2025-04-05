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
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20 } from "node_modules/recoverable-wrapper/node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { SystemCallable } from "./consensus/SystemCallable.sol";
import { IRWTEL, ExtCall } from "./interfaces/IRWTEL.sol";

/// @title Recoverable Wrapped Telcoin
/// @notice The RWTEL module serves as an Axelar InterchainToken merging functionality of TEL
/// both as ITS ERC20 token and as native gas currency for TN
/// @dev Inbound ERC20 TEL from other networks is delivered as native TEL through custom mint logic
/// whereas outbound native TEL must first be double-wrapped, with `wTEL::deposit()` and then `rwTEL::wrap()`
/// For security, only RWTEL balances settled by elapsing the recoverable window can be bridged
contract RWTEL is IRWTEL, RecoverableWrapper, InterchainTokenStandard, UUPSUpgradeable, Ownable, SystemCallable {
    /// @dev StakeManager system precompile assigned by protocol to a constant address
    address public constant stakeManager = 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1;

    /// @dev The precompiled Axelar ITS TokenManager contract address for this token
    address public immutable tokenManager;
    /// @dev The precompiled Axelar ITS contract address for this chain
    address private immutable _interchainTokenService;

    /// @dev Constants for deriving the RWTEL canonical ITS deploy salt, token id, and TokenManager address
    address private immutable canonicalTEL;
    bytes32 private immutable canonicalChainNameHash;
    bytes32 private constant PREFIX_CANONICAL_TOKEN_SALT = keccak256("canonical-token-salt");
    bytes32 private constant PREFIX_INTERCHAIN_TOKEN_ID = keccak256("its-interchain-token-id");
    bytes32 private constant CREATE_DEPLOY_BYTECODE_HASH =
        0xdb4bab1640a2602c9f66f33765d12be4af115accf74b24515702961e82a71327;
    /// @notice Token factory flag to be create3-agnostic; see `InterchainTokenService::TOKEN_FACTORY_DEPLOYER`
    address private constant TOKEN_FACTORY_DEPLOYER = address(0x0);

    /// @dev Overrides for `ERC20` storage since `RecoverableWrapper` dep restricts them
    string internal constant _name_ = "Recoverable Wrapped Telcoin";
    string internal constant _symbol_ = "rwTEL";

    uint256 public constant DECIMALS_CONVERTER = 10e16;

    modifier onlyTokenManager() {
        if (msg.sender != tokenManager) revert OnlyManager(tokenManager);
        _;
    }

    /// @dev Required by `RecoverableWrapper` and `AxelarGMPExecutable` deps to write immutable vars to bytecode
    /// @param name_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    /// @param symbol_ Not used; required for `RecoverableWrapper::constructor()` but is overridden
    constructor(
        address canonicalTEL_,
        string memory canonicalChainName_,
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
        canonicalTEL = canonicalTEL_;
        canonicalChainNameHash = keccak256(bytes(canonicalChainName_));
        tokenManager = tokenManagerAddress();
    }

    /// @inheritdoc IRWTEL
    function distributeStakeReward(address validator, uint256 rewardAmount) external virtual {
        if (msg.sender != stakeManager) revert OnlyManager(stakeManager);

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

    /// @inheritdoc InterchainTokenStandard
    function interchainTokenService() public view virtual override returns (address service) {
        return _interchainTokenService;
    }

    /**
     *
     *   Axelar Interchain Token Service
     *
     */

    /// @inheritdoc IRWTEL
    function mint(
        address to,
        uint256 canonicalAmount
    )
        external
        virtual
        override
        onlyTokenManager
        returns (uint256 nativeAmount)
    {
        nativeAmount = convertInterchainTELDecimals(canonicalAmount);

        (bool r,) = to.call{ value: nativeAmount }("");
        if (!r) revert MintFailed(to, nativeAmount);
    }

    /// @inheritdoc IRWTEL
    function burn(
        address from,
        uint256 nativeAmount
    )
        external
        virtual
        override
        onlyTokenManager
        returns (uint256 canonicalAmount)
    {
        // burn and reclaim native TEL to maintain integrity of rwTEL <> wTEL <> TEL ledgers
        _burn(from, nativeAmount);
        (bool r,) = address(baseERC20).call(abi.encodeWithSignature("withdraw(uint256)", nativeAmount));
        if (!r) revert BurnFailed(from, nativeAmount);

        canonicalAmount = convertNativeTELDecimals(nativeAmount);
    }

    /// @inheritdoc IRWTEL
    function isMinter(address addr) external view virtual returns (bool) {
        if (addr == tokenManagerAddress()) return true;

        return false;
    }

    /// @inheritdoc IRWTEL
    function convertInterchainTELDecimals(uint256 erc20TELAmount) public pure returns (uint256 nativeTELAmount) {
        nativeTELAmount = erc20TELAmount * DECIMALS_CONVERTER;
    }
    //todo precisionhandling

    /// @inheritdoc IRWTEL
    function convertNativeTELDecimals(uint256 nativeTELAmount) public pure returns (uint256 erc20TELAmount) {
        erc20TELAmount = nativeTELAmount / DECIMALS_CONVERTER;
        //todo: send truncated remainder back to user for future gas amounts
    }

    /// @inheritdoc IRWTEL
    function tokenManagerCreate3Salt() public view override returns (bytes32) {
        return interchainTokenId();
    }

    /// @notice Returns the top-level ITS interchain token ID for RWTEL
    /// @dev The interchain token ID is *canonical*, ie based on Ethereum ERC20 TEL, and shared across chains
    function interchainTokenId() public view override returns (bytes32) {
        return keccak256(
            abi.encode(PREFIX_INTERCHAIN_TOKEN_ID, TOKEN_FACTORY_DEPLOYER, canonicalInterchainTokenDeploySalt())
        );
    }

    /// @inheritdoc IRWTEL
    function canonicalInterchainTokenDeploySalt() public view override returns (bytes32) {
        // note chain namehash for Ethereum canonical TEL is used since `itFactory&&its::chainNameHash()` are for TN
        return keccak256(abi.encode(PREFIX_CANONICAL_TOKEN_SALT, canonicalChainNameHash, canonicalTEL));
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
}
