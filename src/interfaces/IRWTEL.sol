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
    error OnlyConsensusRegistry();
    error RewardDistributionFailure(address validator);
    error ExecutionFailed(bytes32 commandId, address target);
    error InvalidToken(bytes32 commandId, address token, bytes32 tokenId);
    error InvalidTarget(bytes32 commandId, address target);
    error InvalidAmount(bytes32 commandId, uint256 amount, uint256 extCallAmount);

    /// @notice May only be called by the ConsensusRegistry as part of its `claimStakeRewards()` flow
    function distributeStakeReward(address validator, uint256 rewardAmount) external;

    /// @notice Transfers RWTEL using RecoverableWrapper state updates and custom logic for Axelar ITS
    /// @dev Overridden because RWTEL TokenManager bridging (`LOCK_UNLOCK`) uses `safeTransferFrom`
    function safetransferfrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the Axelar ITS custom salt for RWTEL
    function canonicalInterchainTokenId() external view returns (bytes32);

    /// @notice Returns the unique salt required for RWTEL ITS integration
    /// @dev Equivalent to `InterchainTokenFactory::canonicalInterchainTokenDeploySalt()`
    function canonicalInterchainTokenDeploySalt() external view returns (bytes32);

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
}
