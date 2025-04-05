// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { AxelarGMPExecutable } from
    "@axelar-cgp-solidity/node_modules/@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarGMPExecutable.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";

/// @dev Designed for AxelarGMPExecutable's required implementation of `_execute()`
struct ExtCall {
    address target;
    uint256 value;
    bytes data;
}

interface IRWTEL {
    error OnlyManager(address authority);
    error RewardDistributionFailure(address validator);
    error MintFailed(address to, uint256 amount);
    error BurnFailed(address from, uint256 amount);

    /// @notice May only be called by the StakeManager as part of its `claimStakeRewards()` flow
    function distributeStakeReward(address validator, uint256 rewardAmount) external;

    /// @notice Returns the create3 salt used by ITS for TokenManager deployment
    /// @dev This salt is used to deploy/derive TokenManagers for both Ethereum and TN
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerCreate3Salt() external view returns (bytes32);

    /// @notice Returns the unique salt required for RWTEL ITS integration
    /// @dev Equivalent to `InterchainTokenFactory::canonicalInterchainTokenDeploySalt()`
    function canonicalInterchainTokenDeploySalt() external view returns (bytes32);

    /// @notice Returns the ITS TokenManager address for RWTEL, derived via create3
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerAddress() external view returns (address);

    /// @notice Replaces `constructor` for use when deployed as a proxy implementation
    /// @notice `RW::constructor()` accepts a `baseERC20_` parameter which is set as an immutable variable in bytecode
    /// @dev This function and all functions invoked within are only available on devnet and testnet
    /// Since it will never change, no assembly workaround function such as `setMaxToClean()` is implemented
    function initialize(address governanceAddress_, uint16 maxToClean_, address owner_) external;

    /// @dev Permissioned setter functions
    function setGovernanceAddress(address newGovernanceAddress) external;
    /// @notice Workaround function to alter `RecoverableWrapper::MAX_TO_CLEAN` without forking audited code
    /// Provided because `MAX_TO_CLEAN` may require alteration in the future, as opposed to `baseERC20`,
    /// @dev `MAX_TO_CLEAN` is stored in slot 11
    function setMaxToClean(uint16 newMaxToClean) external;

    /// @notice Required by Axelar ITS to complete interchain transfers during payload processing
    /// of `MESSAGE_TYPE_INTERCHAIN_TRANSFER` headers, which delegatecalls `TokenHandler::giveToken()`
    function isMinter(address addr) external view returns (bool);

    /// @notice TN equivalent of `IERC20MintableBurnable::burn()` handling cross chain `ERC20::decimals` and native TEL
    /// @dev Burns and reclaims native amount from settled (recoverable) balance, returns canonical amount to TNTokenManager
    /// @return nativeAmount The native TEL amount converted to 18 decimals from the 2 of ERC20 TEL on remote chains
    function mint(address to, uint256 canonicalAmount) external returns (uint256 nativeAmount);

    /// @notice TN equivalent of `IERC20MintableBurnable::burn()` handling cross chain `ERC20::decimals` and native TEL
    /// @dev Burns and reclaims native amount from settled (recoverable) balance, returns canonical amount to TNTokenManager
    /// @return canonicalAmount The canonical TEL ERC20 amount converted to 2 decimals from the 18 of native & wTEL
    function burn(address from, uint256 nativeAmount) external returns (uint256 canonicalAmount);

    /// @notice Handles decimal conversion of remote ERC20 TEL to native TEL
    function convertInterchainTELDecimals(uint256 erc20TELAmount) external pure returns (uint256 nativeTELAmount);

    /// @notice Handles decimal conversion of native TEL to remote ERC20 TEL
    /// @notice Excess native TEL remainder from truncating 16 decimals is refunded to the user for future gas usage
    function convertNativeTELDecimals(uint256 nativeTELAmount) external pure returns (uint256 erc20TELAmount);
}
