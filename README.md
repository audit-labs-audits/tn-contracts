## Telcoin Network Smart Contracts

### ConsensusRegistry

#### Role

The Telcoin Network ConsensusRegistry contract serves as a single onchain source of truth for consensus-related items which need to be easily accessible across all TN nodes.

These items include

1.  **ConsensusNFT Whitelist** To onboard, new validators must obtain a `ConsensusNFT` through Telcoin governance. The ConsensusRegistry contract manages this NFT ledger.
2.  Managing TEL staking mechanisms, such as locking stake for governance-approved validators as well as tracking and distributing (pull-based) rewards for validation services
3.  Managing the active validator set, autonomously bringing them through pending queues for activation and exit
4.  Storing historical epoch information which includes epoch block heights and voting validator committees. Voter committees are predetermined by the protocol and stored two epochs in the future.

To keep this information up to date, the protocol maintains contract state via the use of a system call to `ConsensusRegistry::finalizePreviousEpoch()` at the end of each epoch. This action is what kickstarts the beginning of each new epoch.

#### Mechanisms

##### The contract's most frequent entrypoint: `finalizePreviousEpoch()`

- **Finalize Epoch:** The `finalizePreviousEpoch` function is responsible for finalizing the previous epoch, updating the validator set, storing new epoch information, and incrementing staking rewards. Rewards may then be claimed by validators at their discretion.
- **System Call Context** `finalizePreviousEpoch()` may only be called by the client via `system call`, which occurs every epoch. This logic is abstracted into the `SystemCallable` module.

##### ConsensusNFT Whitelist

To join Telcoin Network as a validator, node operators first must be approved by Telcoin governance. Once approved, validators will be issued a `ConsensusNFT` serving as a permissioned validator whitelist. Only the contract owner, an address managed by Telcoin governance, can issue these NFTs via `ConsensusRegistry::mint()`

The ERC721 `tokenId` of each validator's token corresponds to their validator uid, termed `validatorIndex` in the registry's implementation.

##### Validator Registration and Staking

Once issued a `ConsensusNFT`, validators may enter the pending activation queue at their discretion by staking a fixed amount of native TEL and providing their public keys via `ConsensusRegistry::stake()`

Below, we follow the general lifecycle of a new validator in roughly chronological order.

1. **Validator Registration**

   - **Stake:** Validators with a `ConsensusNFT` call the `stake()` function along with the required stake amount, providing their BLS public key, BLS signature, and ED25519 public key.
   - **Pending Activation:** Upon successful staking, the validator's status is set to `PendingActivation`, and its activation epoch is recorded to be 2 epochs in the future. After awaiting the remainder of the current epoch and then one full epoch, its status will automatically be updated to `Active`

2. **Activation**

   - **Epoch Advancement:** At the end of each epoch, the `finalizePreviousEpoch()` function is system called directly from the client. This function automatically processes the `PendingActivation` and `PendingExit` queues. Thus, validators in the `PendingActivation` (or `PendingExit`) state are set to `Active` (or `Exited`) state if their activation (or exit) epoch has been reached by advancing an epoch.

3. **Reversible Exit**

   - **Exit Requests** Once active, validators may call the `exit()` function to initiate an exit from the network. These exits are reversible and may be used for node maintenance or key rotation. To permanently forgoe validator status, exited validators must then reclaim their stake and burn their ConsensusNFT using `unstake()`
   - **Pending Exit** Upon calling `exit()`, the validator's status is set to `PendingExit`, and their exit epoch is recorded to be 2 epochs in the future. The pending queue is handled identically to the `PendingActivation` process described above.

4. **Rejoining**

   - **Rejoin Requests** Once exited, validators may call the `rejoin()` function to initiate a rejoin request. They may provide new keys if desired.
   - **Pending Activation** Upon calling `rejoin()`, the validator will be entered into the `PendingActivation` queue

5. **Unstaking**
   - **Withdraw Stake:** Once in the `Exited` state, validators can call the `unstake` function to withdraw their original stake amount along with any accrued rewards.
   - Once unstaked, a validator can no longer `rejoin()`, as their `ConsensusNFT` is burned and their validator is set to `UNSTAKED` state, which is unrecoverable. Should an unstaked validator want to resume validating the network, they must reapply to Telcoin governance and be re-issued a new `ConsensusNFT`

#### ConsensusRegistry storage layout for genesis

The registry contract uses explicit namespaced storage to sandbox sensitive state by category and prevent potential overwrites during upgrades (it is an upgradeable proxy for testnet +devnet). Namespaced sections are separated by "---" blocks

##### Static types and hashmap preimages

| Name               | Type                          | Slot                                                                 | Offset   | Bytes   |
| ------------------ | ----------------------------- | -------------------------------------------------------------------- | -------- | ------- |
| \implementation    | address                       | 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC   | 0        | 32      |
| \_initialized      | uint64                        | 0xF0C57E16840DF040F15088DC2F81FE391C3923BEC73E23A9662EFC9C229C6A00   | 0        | 32      |
| \_paused           | bool                          | 0                                                                    | 0        | 1       |
| \_owner            | address                       | 0                                                                    | 1        | 20      |
| ------------------ | ----------------------------- | -------------------------------------------------------------------- | -------- | ------- |
| \_name             | string                        | 0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079300   | 0        | 32      |
| \_symbol           | string                        | 0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079301   | 0        | 32      |
| ------------------ | ----------------------------- | -------------------------------------------------------------------- | -------- | ------- |
| rwTEL              | address                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400   | 12       | 20      |
| stakeAmount        | uint256                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7401   | 0        | 32      |
| minWithdrawAmount  | uint256                       | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7402   | 0        | 32      |
| stakeInfo          | mapping(address => StakeInfo) | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7403   | 0        | s       |
| ------------------ | ----------------------------- | -------------------------------------------------------------------- | -------- | ------- |
| currentEpoch       | uint32                        | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100   | 0        | 4       |
| epochPointer       | uint8                         | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100   | 4        | 1       |
| epochInfo          | EpochInfo[4]                  | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101-8 | 0        | x       |
| futureEpochInfo    | FutureEpochInfo[4]            | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23109-c | 0        | y       |
| validators         | ValidatorInfo[]               | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f2310d   | 0        | z       |

##### Storage locations for dynamic variables

- `stakeInfo` content (s) is derived using `keccak256(abi.encodePacked(bytes32(keyAddr), stakeInfo.slot))`
- `epochInfo` (x) begins at slot `0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101` and spans four static array members through slot `0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23108`
- `futureEpochInfo` (y) begins at slot `0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23109` and spans four static array members through slot `0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f2310c`
- `validators` (z) begins at slot `0x8127b3d06d1bc4fc33994fe62c6bb5ac3963bb2d1bcb96f34a40e1bdc5624a27` and spans slots equal to 3x the total number of validators, because each `ValidatorInfo` member occupies 3 slots. It is worth noting that the first three slots belong to an undefined and unused validator with `validatorIndex == 0`
