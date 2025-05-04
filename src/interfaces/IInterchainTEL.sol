// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { AxelarGMPExecutable } from
    "@axelar-cgp-solidity/node_modules/@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarGMPExecutable.sol";
import { RecoverableWrapper } from "recoverable-wrapper/contracts/rwt/RecoverableWrapper.sol";
import { Record } from "recoverable-wrapper/contracts/util/RecordUtil.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable } from "solady/auth/Ownable.sol";

interface IInterchainTEL {
    event RemainderTransferFailed(address indexed to, uint256 amount);

    error OnlyTokenManager(address manager);
    error OnlyBaseToken(address wTEL);
    error PermitWrapFailed(address to, uint256 amount);
    error MintFailed(address to, uint256 amount);
    error BurnFailed(address from, uint256 amount);
    error InvalidAmount(uint256 nativeAmount);

    /// @notice Convenience function for users to wrap native TEL directly to iTEL in one tx
    /// @dev InterchainTEL performs WETH9 deposit on behalf of caller so they need not hold wTEL or make approval
    function doubleWrap() external payable;

    /// @notice Convenience function for users to wrap wTEL to iTEL in one tx without approval
    /// @dev Explicitly allows malleable signatures for optionality. Malleability is handled
    /// by abstracting signature reusability away via stateful nonce within the EIP-712 structhash
    function permitWrap(
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        payable;

    /// @notice Fetches the account's outstanding unsettled records
    /// @dev Intended as a convenience function only, eg for frontends. Does not prevent
    /// reverts arising from unbounded storage access
    function unsettledRecords(address account) external view returns (Record[] memory);

    /// @notice Returns the create3 salt used by ITS for TokenManager deployment
    /// @dev This salt is used to deploy/derive TokenManagers for both Ethereum and TN
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerCreate3Salt() external view returns (bytes32);

    /// @notice Returns the unique salt required for InterchainTEL ITS integration
    /// @dev Equivalent to `InterchainTokenFactory::linkedTokenDeploySalt()`
    function linkedTokenDeploySalt() external view returns (bytes32);

    /// @notice Returns the ITS TokenManager address for InterchainTEL, derived via create3
    /// @dev ITS uses `interchainTokenId()` as the create3 salt used to deploy TokenManagers
    function tokenManagerAddress() external view returns (address);

    /// @notice Required by Axelar ITS to complete interchain transfers during payload processing
    /// of `MESSAGE_TYPE_INTERCHAIN_TRANSFER` headers, which delegatecalls `TokenHandler::giveToken()`
    function isMinter(address addr) external view returns (bool);

    /// @notice TN equivalent of `IERC20MintableBurnable::burn()` handling cross chain `ERC20::decimals` and native TEL
    /// @dev Mints native TEL to `to`, returning the converted native decimal amount
    /// @return _ The native TEL amount converted to 18 decimals from the 2 of ERC20 TEL on remote chains
    function mint(address to, uint256 originAmount) external returns (uint256);

    /// @notice TN equivalent of `IERC20MintableBurnable::burn()` handling cross chain `ERC20::decimals` and native TEL
    /// @dev Burns & reclaims native TEL from settled (recoverable) balance, returning origin decimal amount
    /// @return _ The origin TEL ERC20 amount converted to 2 decimals from the 18 of native & wTEL
    function burn(address from, uint256 nativeAmount) external returns (uint256);

    /// @notice Handles decimal conversion of remote ERC20 TEL to native TEL
    function toEighteenDecimals(uint256 erc20TELAmount) external pure returns (uint256);

    /// @notice Handles decimal conversion of native TEL to remote ERC20 TEL
    /// @notice Excess native TEL remainder from truncating 16 decimals is refunded to the user for future gas usage
    function toTwoDecimals(uint256 nativeTELAmount) external pure returns (uint256, uint256);

    function transferGovernance(address newGovernanceAddress) external; //todo
}
