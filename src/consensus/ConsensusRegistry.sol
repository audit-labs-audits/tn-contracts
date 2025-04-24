// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { IncentiveInfo, IStakeManager } from "./interfaces/IStakeManager.sol";
import { StakeManager } from "./StakeManager.sol";
import { IConsensusRegistry } from "./interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "./SystemCallable.sol";

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is
    StakeManager,
    UUPSUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    SystemCallable,
    IConsensusRegistry
{
    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.ConsensusRegistry")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant ConsensusRegistryStorageSlot =
        0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

    /// @dev Signals a validator's pending status until activation/exit to correctly apply incentives
    uint32 internal constant PENDING_EPOCH = type(uint32).max;

    /// @dev Addresses precision loss for incentives calculations
    uint256 internal constant PRECISION_FACTOR = 1e32;

    /**
     *
     *   consensus
     *
     */

    /// @inheritdoc IConsensusRegistry
    function concludeEpoch(
        address[] calldata newCommittee,
        IncentiveInfo[] calldata slashes
    )
        external
        override
        onlySystemCall
    {
        // update epoch ring buffer info, validator queue
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        (uint32 newEpoch, uint32 duration) = _updateEpochInfo($, newCommittee);
        _updateValidatorQueue($, newCommittee, newEpoch);

        // assert new epoch committee is valid against total now eligible
        ValidatorInfo[] memory newActive = _getValidators($, ValidatorStatus.Active);
        _checkCommitteeSize(newActive.length, newCommittee.length);

        applyIncentives(newEpoch, newActive, slashes);

        emit NewEpoch(EpochInfo(newCommittee, uint64(block.number + 1), duration));
    }

    /// @notice Slashing is not live but scaffolding for it is included here. For the time being,
    /// system calls to this function provide an empty calldata array
    /// @inheritdoc IConsensusRegistry
    function applyIncentives(
        uint32 newEpoch,
        ValidatorInfo[] memory active,
        IncentiveInfo[] calldata /*slashes*/
    )
        public
        override
        onlySystemCall
    {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        uint8 currentVersion = stakeVersion();
        StakeConfig memory currentConfig = stakeConfig(currentVersion);
        (address[] memory recipients, uint256[] memory stakes, uint256 totalStake) =
            _eligibleStakerParams($S, active, newEpoch, currentVersion, currentConfig);

        // calculate and apply proportional rewards
        uint256 totalIssuance = currentConfig.epochIssuance;
        for (uint256 i; i < recipients.length; ++i) {
            uint256 stakeProportion = stakes[i] * PRECISION_FACTOR / totalStake;
            uint256 reward = totalIssuance * stakeProportion / PRECISION_FACTOR;

            // increment claimable amount
            $S.incentiveInfo[recipients[i]].stakingRewards += uint232(reward);
        }

        // to be more lenient, slashing would happen after rewards are applied
        // _applySlashes($S, slashes);
    }

    /// @inheritdoc IConsensusRegistry
    function getCurrentEpoch() public view returns (uint32) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return $.currentEpoch;
    }

    /// @inheritdoc IConsensusRegistry
    function getCurrentEpochInfo() public view returns (EpochInfo memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        return _getRecentEpochInfo($, $.currentEpoch, $.currentEpoch, $.epochPointer);
    }

    /// @inheritdoc IConsensusRegistry
    function getEpochInfo(uint32 epoch) public view returns (EpochInfo memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint32 currentEpoch = $.currentEpoch;
        if (epoch > currentEpoch + 2 || (currentEpoch >= 3 && epoch < currentEpoch - 3)) {
            revert InvalidEpoch(epoch);
        }

        uint8 currentPointer = $.epochPointer;
        if (epoch > currentEpoch) {
            return _getFutureEpochInfo($, epoch, currentEpoch, currentPointer);
        } else {
            return _getRecentEpochInfo($, epoch, currentEpoch, currentPointer);
        }
    }

    /// @inheritdoc IConsensusRegistry
    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        if (status == ValidatorStatus.Undefined) revert InvalidStatus(status);

        return _getValidators(_consensusRegistryStorage(), status);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorTokenId(address validatorAddress) public view returns (uint256) {
        return _checkKnownValidator(_stakeManagerStorage(), validatorAddress);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorByTokenId(uint256 tokenId) public view returns (ValidatorInfo memory) {
        if (!_exists(tokenId)) revert InvalidTokenId(tokenId);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        return $.validators[uint24(tokenId)];
    }

    /// @inheritdoc IConsensusRegistry
    function isRetired(uint256 tokenId) public view returns (bool) {
        // tokenId cannot be in use, `0`, `UNSTAKED`, or out of uint24 bounds
        if (_exists(tokenId)) revert InvalidTokenId(tokenId);

        return _consensusRegistryStorage().validators[uint24(tokenId)].isRetired;
    }

    /// @inheritdoc StakeManager
    function delegationDigest(
        bytes memory blsPubkey,
        address validatorAddress,
        address delegator
    )
        external
        view
        override
        returns (bytes32)
    {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        uint24 tokenId = _checkKnownValidator($S, validatorAddress);
        uint64 nonce = $S.delegations[validatorAddress].nonce;
        bytes32 blsPubkeyHash = keccak256(blsPubkey);
        bytes32 structHash =
            keccak256(abi.encode(DELEGATION_TYPEHASH, blsPubkeyHash, delegator, tokenId, $S.stakeVersion, nonce));

        return _hashTypedData(structHash);
    }

    /**
     *
     *   validators
     *
     */

    /// @inheritdoc StakeManager
    function stake(bytes calldata blsPubkey) external payable override whenNotPaused {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();

        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        StakeManagerStorage storage $S = _stakeManagerStorage();
        _checkStakeValue(msg.value, $S.stakeVersion);
        uint24 tokenId = _checkKnownValidator($S, msg.sender);
        // require validator has not yet staked
        _checkValidatorStatus(_consensusRegistryStorage(), tokenId, ValidatorStatus.Undefined);

        // enter validator in activation queue
        _recordStaked(blsPubkey, msg.sender, false, $S.stakeVersion, tokenId);
    }

    /// @inheritdoc StakeManager
    function delegateStake(
        bytes calldata blsPubkey,
        address validatorAddress,
        bytes calldata validatorSig
    )
        external
        payable
        override
        whenNotPaused
    {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();

        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        StakeManagerStorage storage $S = _stakeManagerStorage();
        uint8 validatorVersion = $S.stakeVersion;
        _checkStakeValue(msg.value, validatorVersion);
        uint24 tokenId = _checkKnownValidator($S, validatorAddress);

        // require validator status is `Undefined`
        _checkValidatorStatus(_consensusRegistryStorage(), tokenId, ValidatorStatus.Undefined);
        uint64 nonce = $S.delegations[validatorAddress].nonce++;
        bytes32 blsPubkeyHash = keccak256(blsPubkey);

        // governance may utilize white-glove onboarding or offchain agreements
        if (msg.sender != owner()) {
            bytes32 structHash =
                keccak256(abi.encode(DELEGATION_TYPEHASH, blsPubkeyHash, msg.sender, tokenId, validatorVersion, nonce));
            bytes32 digest = _hashTypedData(structHash);
            if (!SignatureCheckerLib.isValidSignatureNowCalldata(validatorAddress, digest, validatorSig)) {
                revert NotValidator(validatorAddress);
            }
        }

        $S.delegations[validatorAddress] = Delegation(blsPubkeyHash, msg.sender, tokenId, validatorVersion, nonce);
        _recordStaked(blsPubkey, validatorAddress, true, validatorVersion, tokenId);
    }

    /// @inheritdoc IConsensusRegistry
    function activate() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        // require caller status is `Staked`
        _checkValidatorStatus($C, tokenId, ValidatorStatus.Staked);

        ValidatorInfo storage validator = $C.validators[tokenId];
        // begin validator activation, completing automatically next epoch
        _beginActivation(validator, $C.currentEpoch);
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards(address validatorAddress) external override whenNotPaused {
        StakeManagerStorage storage $ = _stakeManagerStorage();

        // require validator is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($, validatorAddress);
        uint8 validatorVersion = _consensusRegistryStorage().validators[tokenId].stakeVersion;

        // require caller is either the validator or its delegator
        address recipient = validatorAddress;
        if (msg.sender != validatorAddress) recipient = _checkKnownDelegation($, validatorAddress, msg.sender);
        uint256 rewards = _claimStakeRewards($, validatorAddress, recipient, validatorVersion);

        emit RewardsClaimed(recipient, rewards);
    }

    /// @inheritdoc IConsensusRegistry
    function beginExit() external whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        // disallow filling up the exit queue
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint256 numActive = _getValidators($, ValidatorStatus.Active).length;
        uint256 committeeSize = $.epochInfo[$.epochPointer].committee.length;
        _checkCommitteeSize(numActive, committeeSize);

        // require caller status is `Active` and `currentEpoch >= activationEpoch`
        _checkValidatorStatus($, tokenId, ValidatorStatus.Active);
        ValidatorInfo storage validator = $.validators[tokenId];
        uint32 currentEpoch = $.currentEpoch;
        if (currentEpoch < $.validators[tokenId].activationEpoch) {
            revert InvalidEpoch(currentEpoch);
        }

        // enter validator in pending exit queue
        _beginExit(validator);
    }

    /// @inheritdoc StakeManager
    function unstake(address validatorAddress) external override whenNotPaused {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require validator is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, validatorAddress);

        // require caller is either the validator or its delegator
        address recipient = validatorAddress;
        if (msg.sender != validatorAddress) recipient = _checkKnownDelegation($S, validatorAddress, msg.sender);

        // require validator status is `Exited`
        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        _checkValidatorStatus($C, tokenId, ValidatorStatus.Exited);

        // permanently retire the validator and burn the ConsensusNFT
        ValidatorInfo storage validator = $C.validators[tokenId];
        _retire(validator);

        // return stake and send any outstanding rewards
        uint256 stakeAndRewards = _unstake(validatorAddress, recipient, uint256(tokenId), validator.stakeVersion);

        emit RewardsClaimed(recipient, stakeAndRewards);
    }

    /**
     *
     *   ERC721
     *
     */

    /// @inheritdoc StakeManager
    function mint(address validatorAddress, uint256 tokenId) external override onlyOwner {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        // validators may only possess one token and `validatorAddress` cannot be reused
        if (balanceOf(validatorAddress) != 0 || _getTokenId($, validatorAddress) != 0) {
            revert AlreadyDefined(validatorAddress);
        }

        // set tokenId and increment supply
        $.incentiveInfo[validatorAddress].tokenId = uint24(tokenId);
        uint24 newSupply = ++$.totalSupply;

        // enforce `tokenId` does not exist, is valid, and in incrementing order if not retired
        if (tokenId != newSupply && !isRetired(tokenId)) revert InvalidTokenId(tokenId);

        // issue the ConsensusNFT
        _mint(validatorAddress, tokenId);
    }

    /// @inheritdoc StakeManager
    function burn(address validatorAddress) external override onlyOwner {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require validatorAddress is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, validatorAddress);

        _consensusBurn($S, _consensusRegistryStorage(), tokenId, validatorAddress);
    }

    /**
     *
     *   internals
     *
     */

    /// @notice Enters a validator into the activation queue upon receiving stake
    /// @dev Stores the new validator in the `validators` vector
    function _recordStaked(
        bytes calldata blsPubkey,
        address validatorAddress,
        bool isDelegated,
        uint8 stakeVersion,
        uint24 tokenId
    )
        internal
    {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        ValidatorInfo memory newValidator = ValidatorInfo(
            blsPubkey,
            validatorAddress,
            PENDING_EPOCH,
            uint32(0),
            ValidatorStatus.Staked,
            false,
            isDelegated,
            stakeVersion
        );
        $.validators[tokenId] = newValidator;

        emit ValidatorStaked(newValidator);
    }

    /// @dev Sets the next epoch as activation timestamp for epoch completeness wrt incentives
    function _beginActivation(ValidatorInfo storage validator, uint32 currentEpoch) internal {
        validator.activationEpoch = currentEpoch + 1;
        validator.currentStatus = ValidatorStatus.PendingActivation;

        emit ValidatorPendingActivation(validator);
    }

    /// @dev Activates a validator
    /// @dev Performed by protocol system call at commencement of validator's first full epoch
    function _activate(ValidatorInfo storage validator) internal {
        validator.currentStatus = ValidatorStatus.Active;

        emit ValidatorActivated(validator);
    }

    /// @notice Enters a validator into the exit queue
    /// @dev Finalized by the protocol when the validator is no longer required for committees
    function _beginExit(ValidatorInfo storage validator) internal {
        validator.currentStatus = ValidatorStatus.PendingExit;
        validator.exitEpoch = PENDING_EPOCH;

        emit ValidatorPendingExit(validator);
    }

    /// @notice Exits a validator from the network,
    /// @dev Only invoked via protocol client system call to `concludeEpoch()` or governance ejection
    /// @dev Once exited, the validator may unstake to reclaim their stake and rewards
    function _exit(ValidatorInfo storage validator, uint32 currentEpoch) internal {
        validator.currentStatus = ValidatorStatus.Exited;
        validator.exitEpoch = currentEpoch;

        emit ValidatorExited(validator);
    }

    /// @notice Permanently retires validator from the network by setting invalid status and index
    /// @dev Ensures an validator cannot rejoin after exiting + unstaking or after governance ejection
    /// @dev Rejoining must be done by restarting validator onboarding process
    function _retire(ValidatorInfo storage validator) internal {
        validator.currentStatus = ValidatorStatus.Any;
        validator.isRetired = true;

        emit ValidatorRetired(validator);
    }

    /// @notice Performs activation and/or exit for validators pending in queue where applicable
    /// @dev Validators initiate activation, gaining `PendingActivation` status which resolves to
    /// `Active` at the end of the current epoch. Since they could time activation initiation
    /// with the epoch boundary, they are ineligible for rewards until completing a full epoch
    /// @dev Protocol determines exit eligibility via voter committee assignments across 3 epochs
    function _updateValidatorQueue(
        ConsensusRegistryStorage storage $,
        address[] calldata futureCommittee,
        uint32 currentEpoch
    )
        internal
    {
        ValidatorInfo[] memory pendingActivation = _getValidators($, ValidatorStatus.PendingActivation);
        for (uint256 i; i < pendingActivation.length; ++i) {
            uint24 tokenId = _getTokenId(_stakeManagerStorage(), pendingActivation[i].validatorAddress);
            ValidatorInfo storage activateValidator = $.validators[tokenId];

            _activate(activateValidator);
        }

        ValidatorInfo[] memory pendingExit = _getValidators($, ValidatorStatus.PendingExit);
        for (uint256 i; i < pendingExit.length; ++i) {
            // skip if validator is in current or either future committee
            uint8 currentEpochPointer = $.epochPointer;
            uint8 nextEpochPointer = (currentEpochPointer + 1) % 4;
            address[] memory currentCommittee = $.epochInfo[currentEpochPointer].committee;
            address[] memory nextCommittee = $.futureEpochInfo[nextEpochPointer].committee;
            address validatorAddress = pendingExit[i].validatorAddress;
            if (
                _isCommitteeMember(validatorAddress, currentCommittee)
                    || _isCommitteeMember(validatorAddress, nextCommittee)
                    || _isCommitteeMember(validatorAddress, futureCommittee)
            ) continue;

            uint24 tokenId = _getTokenId(_stakeManagerStorage(), validatorAddress);
            ValidatorInfo storage exitValidator = $.validators[tokenId];
            _exit(exitValidator, currentEpoch);
        }
    }

    /// @notice Forcibly eject a validator from the current, next, and subsequent committees
    /// @dev Intended for sparing use; only reverts if burning results in empty committee
    function _ejectFromCommittees(
        ConsensusRegistryStorage storage $,
        address validatorAddress,
        uint256 numEligible
    )
        internal
    {
        uint32 currentEpoch = $.currentEpoch;
        uint8 currentEpochPointer = $.epochPointer;
        address[] storage currentCommittee =
            _getRecentEpochInfo($, currentEpoch, currentEpoch, currentEpochPointer).committee;
        _checkCommitteeSize(numEligible, currentCommittee.length - 1);
        _eject(currentCommittee, validatorAddress);

        uint32 nextEpoch = currentEpoch + 1;
        address[] storage nextCommittee = _getFutureEpochInfo($, nextEpoch, currentEpoch, currentEpochPointer).committee;
        _checkCommitteeSize(numEligible, nextCommittee.length - 1);
        _eject(nextCommittee, validatorAddress);

        uint32 subsequentEpoch = currentEpoch + 2;
        address[] storage subsequentCommittee =
            _getFutureEpochInfo($, subsequentEpoch, currentEpoch, currentEpochPointer).committee;
        _checkCommitteeSize(numEligible, subsequentCommittee.length - 1);
        _eject(subsequentCommittee, validatorAddress);
    }

    function _eject(address[] storage committee, address validatorAddress) internal {
        uint256 len = committee.length;
        for (uint256 i; i < len; ++i) {
            if (committee[i] == validatorAddress) {
                committee[i] = committee[len - 1];
                committee.pop();

                break;
            }
        }
    }

    function _consensusBurn(
        StakeManagerStorage storage $S,
        ConsensusRegistryStorage storage $C,
        uint24 tokenId,
        address validatorAddress
    )
        internal
    {
        // mark `validatorAddress` as spent using `UNSTAKED`
        $S.incentiveInfo[validatorAddress].tokenId = UNSTAKED;

        // reverts if decremented committee size after ejection reaches 0, preventing network halt
        uint256 numEligible = _getValidators($C, ValidatorStatus.Active).length;
        _ejectFromCommittees($C, validatorAddress, numEligible);

        // exit, retire, and unstake + burn validator immediately
        ValidatorInfo storage validator = $C.validators[tokenId];
        _exit(validator, $C.currentEpoch);
        _retire(validator);
        address recipient = _getRecipient($S, validatorAddress);
        _unstake(validatorAddress, recipient, tokenId, validator.stakeVersion);
    }

    /// @dev Stores the number of blocks finalized in previous epoch and the voter committee for the new epoch
    function _updateEpochInfo(
        ConsensusRegistryStorage storage $,
        address[] memory newCommittee
    )
        internal
        returns (uint32, uint32)
    {
        // cache epoch ring buffer's pointers in memory
        uint8 prevEpochPointer = $.epochPointer;
        uint8 newEpochPointer = (prevEpochPointer + 1) % 4;

        // update new current epoch info
        address[] storage currentCommittee = $.futureEpochInfo[newEpochPointer].committee;
        uint32 newDuration = getCurrentStakeConfig().epochDuration;
        $.epochInfo[newEpochPointer] = EpochInfo(currentCommittee, uint64(block.number), newDuration);
        $.epochPointer = newEpochPointer;
        uint32 newEpoch = ++$.currentEpoch;

        // update future epoch info
        uint8 twoEpochsInFuturePointer = (newEpochPointer + 2) % 4;
        $.futureEpochInfo[twoEpochsInFuturePointer].committee = newCommittee;

        return (newEpoch, newDuration);
    }

    /// @notice Slashing is not live but scaffolding for it is included here.
    function _applySlashes(StakeManagerStorage storage $S, IncentiveInfo[] calldata slashes) internal {
        for (uint256 i; i < slashes.length; ++i) {
            IncentiveInfo calldata slash = slashes[i];
            ValidatorInfo memory validator = getValidatorByTokenId(slash.tokenId);

            uint24 tokenId = _checkKnownValidator($S, validator.validatorAddress);
            if (tokenId != slash.tokenId) revert InvalidTokenId(slash.tokenId);

            uint232 slashAmount = slash.stakingRewards;
            IncentiveInfo storage info = $S.incentiveInfo[validator.validatorAddress];
            if (info.stakingRewards >= slashAmount) {
                info.stakingRewards -= slashAmount;
            } else {
                // in practice this would be early for forced retirement; decrement stake amount first
                _consensusBurn($S, _consensusRegistryStorage(), tokenId, validator.validatorAddress);
            }
        }
    }

    /// @dev Returns eligible recipients, their original stake amount, and the total eligible stake
    /// @dev Validators who were committee-eligible in the concluded epoch will receive rewards
    /// @notice Invoked just after rolling over into a new epoch within `concludeEpoch()`, thus
    /// `currentEpoch && currentVersion && currentConfig` all refer to the new epoch's info
    function _eligibleStakerParams(
        StakeManagerStorage storage $S,
        ValidatorInfo[] memory active,
        uint32 currentEpoch,
        uint8 currentVersion,
        StakeConfig memory currentConfig
    )
        internal
        view
        returns (address[] memory, uint256[] memory, uint256)
    {
        uint256 currentStakeAmount = currentConfig.stakeAmount;
        uint256 numEligible;
        address[] memory tmpRecipients = new address[](active.length);
        uint256[] memory tmpStakes = new uint256[](active.length);
        for (uint256 i; i < active.length; ++i) {
            ValidatorInfo memory validator = active[i];
            // skip validators who just activated and have not yet completed a full epoch
            if (validator.activationEpoch == currentEpoch) continue;

            // gather recipients and their stake amounts using stake their version
            tmpRecipients[numEligible] = _getRecipient($S, validator.validatorAddress);
            uint256 recipientStake;
            if (validator.stakeVersion == currentVersion) {
                recipientStake = currentStakeAmount;
            } else {
                recipientStake = stakeConfig(validator.stakeVersion).stakeAmount;
            }
            tmpStakes[numEligible++] = recipientStake;
        }

        // sum total eligible stake and trim recipient & stake arrays
        uint256 totalStake;
        address[] memory recipients = new address[](numEligible);
        uint256[] memory stakes = new uint256[](numEligible);
        for (uint256 i; i < numEligible; ++i) {
            totalStake += tmpStakes[i];

            stakes[i] = tmpStakes[i];
            recipients[i] = tmpRecipients[i];
        }

        return (recipients, stakes, totalStake);
    }

    /// @dev Fetch info for a future epoch; two epochs into future are stored
    /// @notice Block height is not known for future epochs, so it will be 0
    function _getFutureEpochInfo(
        ConsensusRegistryStorage storage $,
        uint32 futureEpoch,
        uint32 currentEpoch,
        uint8 currentPointer
    )
        internal
        view
        returns (EpochInfo storage)
    {
        uint8 futurePointer = (uint8(futureEpoch - currentEpoch) + currentPointer) % 4;
        return $.futureEpochInfo[futurePointer];
    }

    /// @dev Fetch info for a current or past epoch; four latest are stored (current and three in past)
    function _getRecentEpochInfo(
        ConsensusRegistryStorage storage $,
        uint32 recentEpoch,
        uint32 currentEpoch,
        uint8 currentPointer
    )
        internal
        view
        returns (EpochInfo storage)
    {
        // identify diff from pointer, preventing underflow by adding 4 (will be modulo'd away)
        uint8 pointerDiff = uint8(4 + currentEpoch - recentEpoch);
        uint8 pointer = (currentPointer + pointerDiff) % 4;
        return $.epochInfo[pointer];
    }

    /// @dev Checks current committee size against total eligible for committee service in next epoch
    /// @notice Prevents the network from reaching invalid committee state
    function _checkCommitteeSize(uint256 activeOrPending, uint256 committeeSize) internal pure {
        if (activeOrPending == 0 || committeeSize > activeOrPending) {
            revert InvalidCommitteeSize(activeOrPending, committeeSize);
        }
    }

    /// @dev Identifies the validator's rewards recipient, ie the stake originator
    /// @return _ Returns the validator's delegator if one exists, else the validator itself
    function _getRecipient(StakeManagerStorage storage $S, address validatorAddress) internal view returns (address) {
        Delegation storage delegation = $S.delegations[validatorAddress];
        address recipient = delegation.delegator;
        if (recipient == address(0x0)) recipient = validatorAddress;

        return recipient;
    }

    /// @dev Reverts if provided claimant isn't the existing delegation entry keyed under `validatorAddress`
    function _checkKnownDelegation(
        StakeManagerStorage storage $,
        address validatorAddress,
        address claimant
    )
        internal
        view
        returns (address)
    {
        address delegator = $.delegations[validatorAddress].delegator;
        if (claimant != delegator) revert NotDelegator(claimant);

        return delegator;
    }

    /// @dev Reverts if the provided address doesn't correspond to an existing `tokenId` owned by `validatorAddress`
    function _checkKnownValidator(
        StakeManagerStorage storage $,
        address validatorAddress
    )
        private
        view
        returns (uint24)
    {
        uint24 tokenId = _getTokenId($, validatorAddress);
        if (!_exists(tokenId)) revert InvalidTokenId(tokenId);
        if (ownerOf(tokenId) != validatorAddress) revert NotValidator(validatorAddress);

        return tokenId;
    }

    /// @dev Reverts if the provided validator's status doesn't match the provided `requiredStatus`
    function _checkValidatorStatus(
        ConsensusRegistryStorage storage $,
        uint24 tokenId,
        ValidatorStatus requiredStatus
    )
        private
        view
    {
        ValidatorStatus status = $.validators[tokenId].currentStatus;
        if (status != requiredStatus) revert InvalidStatus(status);
    }

    /// @dev Returns whether given `validatorAddress` is a member of the given committee
    function _isCommitteeMember(address validatorAddress, address[] memory committee) internal pure returns (bool) {
        // cache len to memory
        uint256 committeeLen = committee.length;
        for (uint256 i; i < committeeLen; ++i) {
            // terminate if `validatorAddress` is a member of committee
            if (committee[i] == validatorAddress) return true;
        }

        return false;
    }

    /// @notice `Active` queries also include validators pending activation or exit
    /// Because they are eligible for voter committee service in the next epoch
    /// @dev There are ~1000 total MNOs in the world so `SLOAD` loops should not run out of gas
    /// @dev Room for storage optimization (SSTORE2 etc) to hold more validators
    function _getValidators(
        ConsensusRegistryStorage storage $,
        ValidatorStatus status
    )
        internal
        view
        returns (ValidatorInfo[] memory)
    {
        ValidatorInfo[] memory untrimmed = new ValidatorInfo[](_stakeManagerStorage().totalSupply);
        uint256 numMatches;

        for (uint24 i = 1; i <= untrimmed.length; ++i) {
            ValidatorInfo storage current = $.validators[i];
            if (current.isRetired) continue;

            // queries for `Any` status include all unretired validators
            bool matchFound = status == ValidatorStatus.Any;
            if (!matchFound) {
                // mem cache to save SLOADs
                ValidatorStatus currentStatus = current.currentStatus;

                // include pending activation/exit due to committee service eligibility in next epoch
                if (status == ValidatorStatus.Active) {
                    matchFound = (
                        currentStatus == ValidatorStatus.Active || currentStatus == ValidatorStatus.PendingExit
                            || currentStatus == ValidatorStatus.PendingActivation
                    );
                } else {
                    // all other queries return only exact matches
                    matchFound = currentStatus == status;
                }
            }

            if (matchFound) {
                untrimmed[numMatches++] = current;
            }
        }

        // trim and return final array
        ValidatorInfo[] memory validatorsMatched = new ValidatorInfo[](numMatches);
        for (uint256 i; i < numMatches; ++i) {
            validatorsMatched[i] = untrimmed[i];
        }

        return validatorsMatched;
    }

    function _consensusRegistryStorage() internal pure returns (ConsensusRegistryStorage storage $) {
        assembly {
            $.slot := ConsensusRegistryStorageSlot
        }
    }

    /**
     *
     *   pausability
     *
     */

    /// @dev Emergency function to pause validator and stake management
    /// @notice Does not pause `concludeEpoch()`. Only accessible by `owner`
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Emergency function to unpause validator and stake management
    /// @notice Does not affect `concludeEpoch()`. Only accessible by `owner`
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     *
     *   upgradeability (devnet, testnet)
     *
     */

    /// @notice Not actually used since this contract is precompiled and written to TN at genesis
    /// It is left in the contract for readable information about the relevant storage slots at genesis
    /// @param initialValidators_ The initial validator set running Telcoin Network; these validators will
    /// comprise the voter committee for the first three epochs, ie `epochInfo[0:2]`
    /// @dev ConsensusRegistry contract must be instantiated at genesis with stake for `initialValidators_`
    /// @dev Only governance delegation is enabled at genesis
    function initialize(
        address rwTEL_,
        StakeConfig memory genesisConfig_,
        ValidatorInfo[] memory initialValidators_,
        address owner_
    )
        external
        initializer
    {
        if (initialValidators_.length == 0 || initialValidators_.length > type(uint24).max) {
            revert InitializerArityMismatch();
        }

        __Ownable_init(owner_);
        __Pausable_init();

        StakeManagerStorage storage $S = _stakeManagerStorage();

        // Set stake storage configs
        $S.rwTEL = rwTEL_;
        $S.versions[0] = genesisConfig_;

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();

        // set 0th validator placeholder with invalid values for future checks
        $C.validators[0] =
            ValidatorInfo(hex"ff", address(0xff), uint32(0xff), uint32(0xff), ValidatorStatus.Any, true, true, 0xff);
        for (uint256 i; i < initialValidators_.length; ++i) {
            ValidatorInfo memory currentValidator = initialValidators_[i];

            // assert `validatorIndex` struct members match expected value
            if (currentValidator.blsPubkey.length != 96) {
                revert InvalidBLSPubkey();
            }
            if (currentValidator.validatorAddress == address(0x0)) {
                revert InvalidValidatorAddress();
            }
            if (currentValidator.activationEpoch != uint32(0)) {
                revert InvalidEpoch(currentValidator.activationEpoch);
            }
            if (currentValidator.exitEpoch != uint32(0)) {
                revert InvalidEpoch(currentValidator.exitEpoch);
            }
            if (currentValidator.currentStatus != ValidatorStatus.Active) {
                revert InvalidStatus(currentValidator.currentStatus);
            }
            if (currentValidator.isRetired != false) {
                revert InvalidStatus(ValidatorStatus.Exited);
            }
            uint24 tokenId = uint24(i + 1);
            if (currentValidator.isDelegated == true) {
                // at genesis, only governance delegations are enabled
                $S.delegations[currentValidator.validatorAddress] =
                    Delegation(keccak256(currentValidator.blsPubkey), owner_, tokenId, uint8(0), uint64(1));
            }
            if (currentValidator.stakeVersion != 0) {
                revert InvalidStakeAmount(currentValidator.stakeVersion);
            }

            // first three epochs use initial validators as committee
            for (uint256 j; j <= 2; ++j) {
                EpochInfo storage epochZero = $C.epochInfo[j];
                epochZero.committee.push(currentValidator.validatorAddress);
                epochZero.epochDuration = genesisConfig_.epochDuration;
                $C.futureEpochInfo[j].committee.push(currentValidator.validatorAddress);
            }

            $C.validators[tokenId] = currentValidator;
            $S.incentiveInfo[currentValidator.validatorAddress].tokenId = tokenId;
            $S.totalSupply++;
            __ERC721_init("ConsensusNFT", "CNFT");
            _mint(currentValidator.validatorAddress, tokenId);

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @inheritdoc IStakeManager
    function upgradeStakeVersion(StakeConfig calldata newConfig)
        external
        override
        onlyOwner
        whenNotPaused
        returns (uint8)
    {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        uint8 newVersion = ++$.stakeVersion;
        $.versions[newVersion] = newConfig;

        return newVersion;
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
