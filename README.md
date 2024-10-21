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

| Name                                                     | Type                            | Slot                                                                   | Offset   | Bytes   | Value                                                                                                                                                                                      |
| -------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| \_paused                                                 | bool                            | 0                                                                      | 0        | 1       |                                                                                                                                                                                            |
| \_owner                                                  | address                         | 0                                                                      | 1        | 20      |                                                                                                                                                                                            |
| ------------------------------------------               | ------------------------------- | ---------------------------------------------------------------------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------------------                                                                     |
| rwTEL                                                    | address                         | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7400     | 12       | 20      | 0x7e1                                                                                                                                                                                      |
| stakeAmount                                              | uint256                         | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7401     | 0        | 32      | 1000000000000000000000000                                                                                                                                                                  |
| minWithdrawAmount                                        | uint256                         | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7402     | 0        | 32      | 10000000000000000000000                                                                                                                                                                    |
| stakeInfo                                                | mapping(address => StakeInfo)   | 0x0636e6890fec58b60f710b53efa0ef8de81ca2fddce7e46303a60c9d416c7403     | 0        | s       |                                                                                                                                                                                            |
| ------------------------------------------               | ------------------------------- | ---------------------------------------------------------------------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------------------                                                                     |
| currentEpoch                                             | uint32                          | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100     | 0        | 4       | epochPointer == 0                                                                                                                                                                          |
| epochPointer                                             | uint8                           | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100     | 4        | 1       |                                                                                                                                                                                            |
| epochInfo                                                | EpochInfo[4]                    | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23101     | 0        | x       | committee.length[0] == 1, blockHeight[0] == 0, committee.length[1] == 1, blockHeight[1] == 0, committee.length[2] == 1, blockHeight[2] == 0, committee.length[3] == 0, blockHeight[3] == 0 |
| futureEpochInfo                                          | FutureEpochInfo[4]              | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23102     | 0        | y       | committee.length[0] == 0, committee.length[1] == 0, committee.length[2] == 0, committee.length[3] == 0                                                                                     |
| validators                                               | ValidatorInfo[]                 | 0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23103     | 0        | z       | length == 2                                                                                                                                                                                |
| ------------------------------------------               | ------------------------------- | ---------------------------------------------------------------------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------------------                                                                     |
| implementation                                           | address                         | 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC     | 0        | 32      |                                                                                                                                                                                            |
| \_initialized                                            | uint64                          | 0xF0C57E16840DF040F15088DC2F81FE391C3923BEC73E23A9662EFC9C229C6A00     | 0        | 8       | 1                                                                                                                                                                                          |
| owner                                                    | address                         | 0x9016D09D72D40FDAE2FD8CEAC6B6234C7706214FD39C1CD1E609A0528C199300     | 0        | 20      | 0xc0ffee                                                                                                                                                                                   |
| shortString("ConsensusNFT", length \* 2)                 | bytes                           | 0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079300     | 0        | 32      | 0x436F6E73656E7375734E46540000000000000000000000000000000000000018                                                                                                                         |
| shortString("CNFT", length \* 2)                         | bytes                           | 0x80BB2B638CC20BC4D0A60D66940F3AB4A00C1D7B313497CA82FB0B4AB0079301     | 0        | 32      | 0x434E465400000000000000000000000000000000000000000000000000000008                                                                                                                         |
| keccak256(abi.encodePacked(validator0, \_owners.slot))   | address                         | 0xBDB57EBF9F236E21A27420ACA53E57B3F4D9C46B35290CA11821E608CDAB5F19     | 0        | 32      | \_owners[validator0] == validator0                                                                                                                                                         |
| keccak256(abi.encodePacked(validator0, \_balances.slot)) | uint256                         | 0x89DC4F27410B0F3ACC713877BE759A601621941908FBC40B97C5004C02763CF8     | 0        | 32      | \_balances[validator0] == 1                                                                                                                                                                |
| validators[1].blsPubkey.length                           | uint256                         | 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2A     | 0        | 32      | 193                                                                                                                                                                                        |
| validators[1].ed25519Pubkey                              | bytes32                         | 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2B     | 0        | 32      | 0x011201DEED66C3B3A1B2AFB246B1436FD291A5F4B65E4FF0094A013CD922F803                                                                                                                         |
| validators[1].packed(...)                                | bytes32                         | 0x8127B3D06D1BC4FC33994FE62C6BB5AC3963BB2D1BCB96F34A40E1BDC5624A2C     | 0        | 32      | 20000010000000000000000000000000000000000000000000000000000BABE                                                                                                                            |
| keccak256(abi.encodePacked(validator0, stakeInfo.slot))  | uint256                         | 0xF72EACDC698A36CB279844370E2C8C845481AD672FF1E7EFFA7264BE6D6A9FD2     | 0        | 32      | validatorIndex(1)                                                                                                                                                                          |
| keccak256(epochInfoBaseSlot)                             | address                         | 0x52B83978E270FCD9AF6931F8A7E99A1B79DC8A7AEA355D6241834B19E0A0EC39     | 0        | 32      | epochInfos[0].committee validator0 == 0xBABE                                                                                                                                               |
| keccak256(epochInfoBaseSlot + 2)                         | address[]                       | 0x96A201C8A417846842C79BE2CD1E33440471871A6CF94B34C8F286AAEB24AD6B     | 0        | 32      | epochInfos[1].committee [validator0] == [0xBABE]                                                                                                                                           |
| keccak256(epochInfoBaseSlot + 4)                         | address[]                       | 0x14D1F3AD8599CD8151592DDEADE449F790ADD4D7065A031FBE8F7DBB1833E0A9     | 0        | 32      | epochInfos[2].committee [validator0] == [0xBABE]                                                                                                                                           |
| keccak256(epochInfoBaseSlot + 6)                         | address[]                       | 0x79AF749CB95FE9CB496550259D0D961DFB54CB2AD0CE32A4118EED13C438A935     | 0        | 32      | epochInfos[3].committee not set == [address(0x0)]                                                                                                                                          |

##### Storage Locations for Dynamic Variables

- `stakeInfo` content (s) begins at slot `0x3b2018e21a7d1a934ee474879a6c46622c725c81fe1ab37a62fbdda1c85e54e4`
- `epochInfo` (x) begins at slot `0x52b83978e270fcd9af6931f8a7e99a1b79dc8a7aea355d6241834b19e0a0ec39` as abi-encoded representation
- `futureEpochInfo` (y) begins at slot `0x3e15a0612117eb21841fac9ea1ce6cd116a911fe4c91a9c367a82cd0c3d79718` as abi-encoded representation
