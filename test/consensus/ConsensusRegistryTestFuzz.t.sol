// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { IConsensusRegistry } from "src/consensus/interfaces/IConsensusRegistry.sol";
import { SystemCallable } from "src/consensus/SystemCallable.sol";
import { StakeManager } from "src/consensus/StakeManager.sol";
import { StakeInfo, IStakeManager } from "src/consensus/interfaces/IStakeManager.sol";
import { RWTEL } from "src/RWTEL.sol";
import { ConsensusRegistryTestUtils } from "./ConsensusRegistryTestUtils.sol";

/// @dev Fuzz test module separated into new file with extra setup to avoid `OutOfGas`
contract ConsensusRegistryTestFuzz is ConsensusRegistryTestUtils, Test {
    function setUp() public {
        consensusRegistry = ConsensusRegistry(0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        vm.etch(address(consensusRegistry), type(ERC1967Proxy).runtimeCode);
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(consensusRegistry), implementationSlot, bytes32(abi.encode(address(consensusRegistryImpl))));
        consensusRegistry.initialize(address(rwTEL), stakeAmount, minWithdrawAmount, initialValidators, crOwner);

        sysAddress = consensusRegistry.SYSTEM_ADDRESS();

        // deal RWTEL max TEL supply to test reward distribution
        vm.deal(address(rwTEL), telMaxSupply);

        // to prevent exceeding block gas limit, `mint(newValidator)` step is performed in setup
        for (uint256 i; i < MAX_MINTABLE; ++i) {
            // account for initial validators
            uint256 tokenId = i + 5;
            address newValidator = _createRandomAddress(tokenId);

            // deal `stakeAmount` funds and prank governance NFT mint to `newValidator`
            vm.deal(newValidator, stakeAmount);
            vm.prank(crOwner);
            consensusRegistry.mint(newValidator, tokenId);
        }
    }

    function testFuzz_concludeEpoch(uint24 numValidators, uint232 fuzzedRewards) public {
        numValidators = uint24(bound(uint256(numValidators), 4, 4000)); // fuzz up to 4k validators
        fuzzedRewards = uint232(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        // activate validators
        for (uint256 i; i < numValidators; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in `setUp()` loop
            uint256 tokenId = i + 5;
            address newValidator = _createRandomAddress(tokenId);

            // create random new validator keys
            bytes memory newBLSPubkey = _createRandomBlsPubkey(tokenId);

            // stake and activate
            vm.deal(newValidator, stakeAmount);
            vm.startPrank(newValidator);
            consensusRegistry.stake{ value: stakeAmount }(newBLSPubkey);
            consensusRegistry.activate();
            vm.stopPrank();
        }

        // identify expected committee size
        uint256 expectedActiveAfter = consensusRegistry.getValidators(ValidatorStatus.Active).length + numValidators;
        uint256 committeeSize;
        if (numValidators <= 6) {
            // 4 initial and 6 new validators will be under the 10 committee size
            committeeSize = expectedActiveAfter;
        } else {
            committeeSize = (expectedActiveAfter * PRECISION_FACTOR) / 3 / PRECISION_FACTOR + 1;
        }

        // reloop to construct `newCommittee` array
        address[] memory newCommittee = new address[](committeeSize);
        uint256 committeeCounter;
        for (uint256 i; i < expectedActiveAfter; ++i) {
            // recreate `newValidator` address minted a ConsensusNFT in `setUp()` loop
            uint256 tokenId = i + 5;
            address newValidator = _createRandomAddress(tokenId);

            // push first third of new validators to new committee
            if (committeeCounter < newCommittee.length) {
                newCommittee[committeeCounter] = newValidator;
                committeeCounter++;
            }
        }

        // conclude epoch to reach activationEpoch for validators entered in stake & activate loop
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](committeeSize));
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.NewEpoch(IConsensusRegistry.EpochInfo(newCommittee, uint64(block.number + 1)));
        consensusRegistry.concludeEpoch(newCommittee);

        uint256 numActiveAfter = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        assertEq(numActiveAfter, expectedActiveAfter);

        // divide total `fuzzedRewards` equally across committee members
        uint256 numRecipients = newCommittee.length;
        uint232 rewardPerValidator = uint232(fuzzedRewards / numRecipients);
        // construct array for `applyIncentives` function call
        StakeInfo[] memory committeeRewards = new StakeInfo[](numRecipients);
        for (uint256 i; i < committeeRewards.length; ++i) {
            uint256 recipientTokenId = consensusRegistry.getValidatorTokenId(newCommittee[i]);
            committeeRewards[i] = StakeInfo(uint24(recipientTokenId), rewardPerValidator);
        }

        // apply incentives by finalizing epoch with `StakeInfo` for constructed committee
        consensusRegistry.incrementRewards(committeeRewards);
        vm.stopPrank();

        console2.logUint(expectedActiveAfter); //todo

        // Check rewards were incremented for each committee member
        for (uint256 i; i < newCommittee.length; ++i) {
            uint256 tokenId = consensusRegistry.getValidatorTokenId(newCommittee[i]);
            address committeeMember = consensusRegistry.getValidatorByTokenId(tokenId).ecdsaPubkey;
            uint256 updatedRewards = consensusRegistry.getRewards(committeeMember);
            assertEq(updatedRewards, rewardPerValidator);
        }
    }

    function testFuzz_claimStakeRewards(uint232 fuzzedRewards) public {
        fuzzedRewards = uint232(bound(uint256(fuzzedRewards), minWithdrawAmount, telMaxSupply));

        // First stake
        vm.prank(validator5);
        consensusRegistry.stake{ value: stakeAmount }(validator5BlsPubkey);

        // Capture initial rewards info
        uint256 initialRewards = consensusRegistry.getRewards(validator5);

        // activate validator5
        vm.prank(validator5);
        consensusRegistry.activate();

        // conclude 2 epochs to reach validator 5 activationEpoch
        uint256 numActive = consensusRegistry.getValidators(ValidatorStatus.Active).length;
        assertEq(numActive, 5);
        vm.startPrank(sysAddress);
        consensusRegistry.concludeEpoch(new address[](numActive));
        consensusRegistry.concludeEpoch(new address[](numActive));

        // Simulate earning rewards by finalizing an epoch with a `StakeInfo` for validator5
        StakeInfo[] memory validator5Rewards = new StakeInfo[](1);
        uint24 tokenId = 5;
        validator5Rewards[0] = StakeInfo(tokenId, fuzzedRewards);
        consensusRegistry.concludeEpoch(new address[](numActive));
        consensusRegistry.incrementRewards(validator5Rewards);
        vm.stopPrank();

        // Check rewards were incremented
        uint256 updatedRewards = consensusRegistry.getRewards(validator5);
        assertEq(updatedRewards, initialRewards + fuzzedRewards);

        // Capture initial validator balance
        uint256 initialBalance = validator5.balance;

        // Check event emission and claim rewards
        vm.expectEmit(true, true, true, true);
        emit IConsensusRegistry.RewardsClaimed(validator5, fuzzedRewards);
        vm.prank(validator5);
        consensusRegistry.claimStakeRewards();

        // Check balance after claiming
        uint256 updatedBalance = validator5.balance;
        assertEq(updatedBalance, initialBalance + fuzzedRewards);
    }
}
