// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { StakeInfo, IStakeManager } from "./interfaces/IStakeManager.sol";
import { StakeManager } from "./StakeManager.sol";
import { IConsensusRegistry } from "./interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "./SystemCallable.sol";

import "forge-std/Test.sol";//todo


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

    /// @dev Addresses precision loss for BFT check calculations; much higher than all MNOs
    uint256 internal constant PRECISION_FACTOR = 1_000_000;

    /**
     *
     *   consensus
     *
     */

    /// @inheritdoc IConsensusRegistry
    function concludeEpoch(address[] calldata newCommittee) external override onlySystemCall {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update epoch and ring buffer info
        uint32 newEpoch = _updateEpochInfo($, newCommittee);
        // update validator queue
        _updateValidatorQueue($, newEpoch);

        // ensure new epoch's canonical network state is still BFT and of expected size
        uint256 numActive = _getValidators($, ValidatorStatus.Active).length;
        // console2.logUint(newCommittee.length); //todo
        _checkFaultTolerance(numActive, newCommittee.length);
        // beyond BFT, committees smaller than 10 also must comprise all active validators
        if (numActive <= 10 && numActive != newCommittee.length) revert InvalidCommitteeSize(numActive, newCommittee.length);

        emit NewEpoch(EpochInfo(newCommittee, uint64(block.number + 1)));
    }

    /// @inheritdoc IStakeManager
    function incrementRewards(StakeInfo[] calldata stakingRewardInfos) external override onlySystemCall {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // update each validator's claimable rewards with given amounts
        uint32 currentEpoch = $.currentEpoch;
        for (uint256 i; i < stakingRewardInfos.length; ++i) {
            console2.logUint(stakingRewardInfos[i].tokenId); //todo
            ValidatorInfo memory currentValidator = getValidatorByTokenId(stakingRewardInfos[i].tokenId);

            // ensure client provided rewards only to known validators that were active for a full epoch
            uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), currentValidator.ecdsaPubkey);
            if (tokenId != stakingRewardInfos[i].tokenId) revert InvalidTokenId(stakingRewardInfos[i].tokenId);
            if (currentValidator.activationEpoch > currentEpoch) {
                revert InvalidStatus(ValidatorStatus.PendingActivation);
            }

            uint232 epochReward = stakingRewardInfos[i].stakingRewards;
            _stakeManagerStorage().stakeInfo[currentValidator.ecdsaPubkey].stakingRewards += epochReward;
        }
    }

    /// @inheritdoc IConsensusRegistry
    function getCurrentEpoch() public view returns (uint32) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return $.currentEpoch;
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
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /// @inheritdoc IConsensusRegistry
    function getValidatorTokenId(address ecdsaPubkey) public view returns (uint256) {
        return _checkKnownValidator(_stakeManagerStorage(), ecdsaPubkey);
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

    /**
     *
     *   validators
     *
     */

    /// @inheritdoc StakeManager
    function stake(bytes calldata blsPubkey) external payable override whenNotPaused {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();
        _checkStakeValue(msg.value);

        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        StakeManagerStorage storage $S = _stakeManagerStorage();
        uint24 tokenId = _checkKnownValidator($S, msg.sender);

        // enter validator in activation queue
        _recordStaked(blsPubkey, msg.sender, false, $S.stakeVersion, tokenId);
    }

    // todo: function stakeFor(bytes calldata blsPubkey, address ecdsaPubkey, bytes calldata validatorSig) external
    // payable override whenNotPaused {
    // if (blsPubkey.length != 96) revert InvalidBLSPubkey();
    // _checkStakeValue(msg.value);

    // StakeManagerStorage storage $S = _stakeManagerStorage();
    // uint24 tokenId = _checkKnownValidator($, ecdsaPubkey);

    // handle dynamic type for blsPubkey a la eip712
    // bytes32 blsPubkeyHash = keccak256(blsPubkey);
    // bytes32 digest = eip712DigestHash(blsPubkeyHash, tokenId);
    // todo: validatorSig represents validator consent to delegation so it must be signed over the blsPubkey hash
    // require( ecdsa.recover(validatorSig) == ecdsaPubkey);

    // delegations[ecdsaPubkey] = msg.sender;
    // _recordStaked(_consensusRegistryStorage(), blsPubkey, ecdsaPubkey, true, $S.stakeVersion, tokenId);
    // }

    /// @inheritdoc IConsensusRegistry
    function activate() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        // require caller status is `PendingActivation`
        _checkValidatorStatus($C, tokenId, ValidatorStatus.PendingActivation);

        ValidatorInfo storage validator = $C.validators[tokenId];
        // activate validator using subsequent epoch for future committee size calculations
        _beginActivation(validator, $C.currentEpoch);
    }

    /// @inheritdoc StakeManager
    function claimStakeRewards() external override whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        StakeManagerStorage storage $ = _stakeManagerStorage();

        //todo: support delegations
        _checkKnownValidator($, msg.sender);
        uint256 rewards = _claimStakeRewards($);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @inheritdoc IConsensusRegistry
    function beginExit() external whenNotPaused {
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator(_stakeManagerStorage(), msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        uint256 numActive = _getValidators($, ValidatorStatus.Active).length;
        uint256 committeeSize = $.epochInfo[$.epochPointer].committee.length;
        _checkFaultTolerance(numActive, committeeSize);

        // require caller status is `Active` and `currentEpoch >= activationEpoch`
        _checkValidatorStatus($, tokenId, ValidatorStatus.Active);
        ValidatorInfo storage validator = $.validators[tokenId];
        uint32 currentEpoch = $.currentEpoch;
        if (currentEpoch < $.validators[tokenId].activationEpoch) {
            revert InvalidEpoch(currentEpoch);
        }

        // enter validator in exit queue
        _beginExit(validator);
    }

    /// @inheritdoc StakeManager
    function unstake() external override whenNotPaused {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, msg.sender); //todo: support delegations

        // require caller status is `Exited`
        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        _checkValidatorStatus($C, tokenId, ValidatorStatus.Exited);

        // burn the ConsensusNFT and permanently retire the validator
        ValidatorInfo storage validator = $C.validators[tokenId];
        _retire(validator);

        // return stake and send any outstanding rewards
        //todo: support delegations
        uint256 stakeAndRewards = _unstake(validator.ecdsaPubkey, uint256(tokenId));

        emit RewardsClaimed(msg.sender, stakeAndRewards);
    }

    /**
     *
     *   ERC721
     *
     */

    /// @inheritdoc StakeManager
    function mint(address ecdsaPubkey, uint256 tokenId) external override onlyOwner {
        StakeManagerStorage storage $ = _stakeManagerStorage();
        // validators may only possess one token and `ecdsaPubkey` cannot be reused
        if (balanceOf(ecdsaPubkey) != 0 || _getTokenId($, ecdsaPubkey) != 0) {
            revert AlreadyDefined(ecdsaPubkey);
        }

        // set tokenId and increment supply
        $.stakeInfo[ecdsaPubkey].tokenId = uint24(tokenId);
        uint24 newSupply = ++$.totalSupply;

        // enforce `tokenId` does not exist, is valid, and in incrementing order if not retired
        if (tokenId != newSupply && !isRetired(tokenId)) revert InvalidTokenId(tokenId);

        // issue the ConsensusNFT
        _mint(ecdsaPubkey, tokenId);
    }

    /// @inheritdoc StakeManager
    function burn(address ecdsaPubkey) external override onlyOwner returns (bool) {
        StakeManagerStorage storage $S = _stakeManagerStorage();
        // require caller is whitelisted, having been issued a ConsensusNFT by governance
        uint24 tokenId = _checkKnownValidator($S, ecdsaPubkey);

        // mark `ecdsaPubkey` as spent using `UNSTAKED`, decrement supply
        $S.stakeInfo[ecdsaPubkey].tokenId = UNSTAKED;
        $S.totalSupply--;

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        ValidatorInfo storage validator = $C.validators[tokenId];
        bool ejected = _ejectFromCommittees($C, ecdsaPubkey);

        // exit, unstake + burn, and retire validator immediately
        _exit(validator, $C.currentEpoch);
        _unstake(ecdsaPubkey, tokenId);
        _retire(validator);

        return ejected;
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
        address ecdsaPubkey,
        bool isDelegated,
        uint8 stakeVersion,
        uint24 tokenId
    )
        internal
    {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        ValidatorInfo memory newValidator = ValidatorInfo(
            blsPubkey,
            ecdsaPubkey,
            PENDING_EPOCH,
            uint32(0),
            ValidatorStatus.PendingActivation,
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

        emit ValidatorPendingActivation(validator);        
    }

    /// @dev Activates a validator
    function _activate(ValidatorInfo storage validator) internal {
        validator.currentStatus = ValidatorStatus.Active;

        emit ValidatorActivated(validator);
    }

    /// @notice Enters a validator into the exit queue
    /// @dev Finalized by the protocol when the validator is no longer required for committees
    function _beginExit(ValidatorInfo storage validator) internal {
        // set validator status to `PendingExit` and set exit epoch
        validator.currentStatus = ValidatorStatus.PendingExit;
        validator.exitEpoch = PENDING_EPOCH;

        emit ValidatorPendingExit(validator);
    }

    /// @notice Exits a validator from the network,
    /// @dev Only invoked via protocol client system call to `concludeEpoch()` or governance ejection
    /// @dev Once exited, the validator may unstake to reclaim their stake and rewards
    function _exit(ValidatorInfo storage validator, uint32 currentEpoch) internal {
        // set validator status to `Exited` and set exit epoch
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
    /// @dev Activation is time-based & automatic at the start of validator's first full epoch
    /// @dev Protocol determines exit eligibility via voter committee assignments across 3 epochs
    /// @dev Invoked via system call within `concludeEpoch()`
    function _updateValidatorQueue(
        ConsensusRegistryStorage storage $,
        uint32 currentEpoch
    )
        internal
    {
        ValidatorInfo[] memory pendingActivation = _getValidators($, ValidatorStatus.PendingActivation);
        for (uint256 i; i < pendingActivation.length; ++i) {
            if (pendingActivation[i].activationEpoch != currentEpoch) continue;

            uint24 tokenId = _getTokenId(_stakeManagerStorage(), pendingActivation[i].ecdsaPubkey);
            ValidatorInfo storage activateValidator = $.validators[tokenId];
            _activate(activateValidator);
        }

        ValidatorInfo[] memory pendingExit = _getValidators($, ValidatorStatus.PendingExit);
        for (uint256 i; i < pendingExit.length; ++i) {
            // ensure validator is not in current or future committees
            address ecdsaPubkey = pendingExit[i].ecdsaPubkey;
            if (_isCurrentCommitteeMember($, ecdsaPubkey) && _isFutureCommitteeMember($, ecdsaPubkey)) continue;

            uint24 tokenId = _getTokenId(_stakeManagerStorage(), ecdsaPubkey);
            ValidatorInfo storage exitValidator = $.validators[tokenId];
            _exit(exitValidator, currentEpoch);
        }
    }

    /// @notice Forcibly eject a validator from the current, next, and subsequent committees
    /// @dev Intended for sparing use; bypasses BFT or committee size checks
    function _ejectFromCommittees(ConsensusRegistryStorage storage $, address ecdsaPubkey) internal returns (bool) {
        bool ejected;

        uint8 currentEpochPointer = $.epochPointer;
        address[] storage currentCommittee = $.epochInfo[currentEpochPointer].committee;
        uint256 len = currentCommittee.length; // cache in memory
        for (uint256 i; i < len; ++i) {
            if (currentCommittee[i] == ecdsaPubkey) {
                currentCommittee[i] = currentCommittee[len - 1];
                currentCommittee.pop();
                ejected = true;
            }
        }

        address[] storage nextCommittee = $.futureEpochInfo[(currentEpochPointer + 1) % 4].committee;
        len = nextCommittee.length;
        for (uint256 i; i < len; ++i) {
            if (nextCommittee[i] == ecdsaPubkey) {
                nextCommittee[i] = nextCommittee[len - 1];
                nextCommittee.pop();
                ejected = true;
            }
        }

        address[] storage subsequentCommittee = $.futureEpochInfo[(currentEpochPointer + 2) % 4].committee;
        len = subsequentCommittee.length;
        for (uint256 i; i < len; ++i) {
            if (subsequentCommittee[i] == ecdsaPubkey) {
                subsequentCommittee[i] = subsequentCommittee[len - 1];
                subsequentCommittee.pop();
                ejected = true;
            }
        }

        return ejected;
    }

    /// @dev Stores the number of blocks finalized in previous epoch and the voter committee for the new epoch
    function _updateEpochInfo(
        ConsensusRegistryStorage storage $,
        address[] memory newCommittee
    )
        internal
        returns (uint32)
    {
        // cache epoch ring buffer's pointers in memory
        uint8 prevEpochPointer = $.epochPointer;
        uint8 newEpochPointer = (prevEpochPointer + 1) % 4;

        // update new current epoch info
        address[] storage currentCommittee = $.futureEpochInfo[newEpochPointer].committee;
        $.epochInfo[newEpochPointer] = EpochInfo(currentCommittee, uint64(block.number));
        $.epochPointer = newEpochPointer;
        uint32 newEpoch = ++$.currentEpoch;

        // update future epoch info
        uint8 twoEpochsInFuturePointer = (newEpochPointer + 2) % 4;
        $.futureEpochInfo[twoEpochsInFuturePointer].committee = newCommittee;

        return (newEpoch);
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
        returns (EpochInfo memory)
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
        returns (EpochInfo memory)
    {
        // identify diff from pointer, preventing underflow by adding 4 (will be modulo'd away)
        uint8 pointerDiff = uint8(recentEpoch + 4 - currentEpoch);
        uint8 pointer = (currentPointer + pointerDiff) % 4;
        return $.epochInfo[pointer];
    }

    /// @dev Checks the given committee size against the total number of active validators using below 3f + 1 BFT rule
    /// @notice Prevents the network from reaching zero active validators (such as by exit)
    function _checkFaultTolerance(uint256 numActive, uint256 committeeSize) internal pure {
        if (numActive == 0) {
            revert InvalidCommitteeSize(0, 0);
        } else if (committeeSize > numActive) {
            // sanity check committee size is less than number of active validators
            revert InvalidCommitteeSize(numActive, committeeSize);
        }

        // if the total validator set is small, all must vote and no faults can be tolerated
        if (numActive <= 4 && committeeSize != numActive) {
            revert InvalidCommitteeSize(numActive, committeeSize);
        } else {
            // calculate number of tolerable faults for given node count using 33% threshold
            uint256 tolerableFaults = (numActive * PRECISION_FACTOR) / 3;

            // committee size must be greater than tolerable faults
            uint256 minCommitteeSize = tolerableFaults / PRECISION_FACTOR + 1;
            if (committeeSize < minCommitteeSize) {
                revert InvalidCommitteeSize(minCommitteeSize, committeeSize);
            }
        }
    }

    /// @dev Reverts if the provided address doesn't correspond to an existing `tokenId` owned by `ecdsaPubkey`
    function _checkKnownValidator(StakeManagerStorage storage $, address ecdsaPubkey) private view returns (uint24) {
        uint24 tokenId = _getTokenId($, ecdsaPubkey);
        if (!_exists(tokenId)) revert InvalidTokenId(tokenId);
        if (ownerOf(tokenId) != ecdsaPubkey) revert NotValidator(ecdsaPubkey);

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

    /// @dev Checks that the given `ecdsaPubkey` is not a member of the next two committees
    function _isCommitteeMember(address ecdsaPubkey, address[] storage committee) internal view returns (bool) {
        // cache len to memory
        uint256 committeeLen = committee.length;
        for (uint256 i; i < committeeLen; ++i) {
            // terminate if `ecdsaPubkey` is a member of current committee
            if (committee[i] == ecdsaPubkey) return true;
        }

        return false;
    }

    /// @dev Returns true if the given `ecdsaPubkey` is on the current committee
    function _isCurrentCommitteeMember(
        ConsensusRegistryStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        returns (bool)
    {
        address[] storage currentCommittee = $.epochInfo[$.epochPointer].committee;
        return _isCommitteeMember(ecdsaPubkey, currentCommittee);
    }

    /// @dev Returns true if the given `ecdsaPubkey` is on either of the next two committees
    function _isFutureCommitteeMember(
        ConsensusRegistryStorage storage $,
        address ecdsaPubkey
    )
        internal
        view
        returns (bool)
    {
        uint8 currentEpochPointer = $.epochPointer;
        uint8 nextEpochPointer = (currentEpochPointer + 1) % 4;
        address[] storage nextCommittee = $.futureEpochInfo[nextEpochPointer].committee;
        if (_isCommitteeMember(ecdsaPubkey, nextCommittee)) return true;

        uint8 twoEpochsInFuturePointer = (currentEpochPointer + 2) % 4;
        address[] storage subsequentCommittee = $.futureEpochInfo[twoEpochsInFuturePointer].committee;
        if (_isCommitteeMember(ecdsaPubkey, subsequentCommittee)) return true;

        return false;
    }

    /// @dev There are ~1400 total MNOs in the world so `SLOAD` loops will not run out of gas
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
        bool getAll = status == ValidatorStatus.Any;
        for (uint256 i = 1; i <= untrimmed.length; ++i) {
            ValidatorInfo storage current = $.validators[uint24(i)];
            if (current.isRetired) continue;

            if (getAll) {
                // query provided `Any` status; grab all unretired
                untrimmed[i - 1] = current;
                ++numMatches;
            } else {
                // query is more granular; grab matches only
                if (current.currentStatus == status) {
                    untrimmed[i - 1] = current;
                    ++numMatches;
                }
            }
        }

        // trim and return final array
        uint256 indexCounter;
        ValidatorInfo[] memory validatorsMatched = new ValidatorInfo[](numMatches);
        for (uint256 i; i < untrimmed.length; ++i) {
            // blsPubkey will be empty for skipped members (non-matches)
            if (untrimmed[i].blsPubkey.length == 0) continue;

            validatorsMatched[indexCounter] = untrimmed[i];
            ++indexCounter;
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
    /// @dev Only governance delegation is enabled at genesis
    function initialize(
        address rwTEL_,
        uint256 stakeAmount_,
        uint256 minWithdrawAmount_,
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
        $S.stakeAmount = stakeAmount_;
        $S.minWithdrawAmount = minWithdrawAmount_;

        ConsensusRegistryStorage storage $C = _consensusRegistryStorage();
        $C.numGenesisValidators = uint8(initialValidators_.length);

        // set 0th validator placeholder with invalid values for future checks
        $C.validators[0] =
            ValidatorInfo(hex"ff", address(0xff), uint32(0xff), uint32(0xff), ValidatorStatus.Any, true, true, 0xff);
        for (uint256 i; i < initialValidators_.length; ++i) {
            ValidatorInfo memory currentValidator = initialValidators_[i];

            // assert `validatorIndex` struct members match expected value
            if (currentValidator.blsPubkey.length != 96) {
                revert InvalidBLSPubkey();
            }
            if (currentValidator.ecdsaPubkey == address(0x0)) {
                revert InvalidECDSAPubkey();
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
            if (currentValidator.isDelegated == true) {
                // at genesis, only governance delegations are enabled
                $C.delegations[currentValidator.ecdsaPubkey] = owner_;
            }
            if (currentValidator.stakeVersion != 0) {
                revert InvalidStakeAmount(currentValidator.stakeVersion);
            }

            // first three epochs use initial validators as committee
            for (uint256 j; j <= 2; ++j) {
                $C.epochInfo[j].committee.push(currentValidator.ecdsaPubkey);
                $C.futureEpochInfo[j].committee.push(currentValidator.ecdsaPubkey);
            }

            uint24 tokenId = uint24(i + 1);
            $C.validators[tokenId] = currentValidator;
            $S.stakeInfo[currentValidator.ecdsaPubkey].tokenId = tokenId;
            $S.totalSupply++;
            __ERC721_init("ConsensusNFT", "CNFT");
            _mint(currentValidator.ecdsaPubkey, tokenId);

            emit ValidatorActivated(currentValidator);
        }
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}
