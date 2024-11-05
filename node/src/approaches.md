- verifier == NVV, watches consensus, performs normal validator duties without voting
- use ampd alongside verifierNVV & axelar as intended

todo:

- implement relayer - markus
- verifier spec
  - runs alongside ampd
  - when poll starts ampd calls `RPCFinalizedBlock` -> latestHeightAndHash on the verifierNVV
  - vote on multisig prover (investigate possible changes)
  - how many? third parties
- deploy contracts - markus

relayer flow:

1. user sends bridge tx to eth mainnet gateway, callContract event is emitted.
2. Subscriber picks up the event (via indexing- ponder?) and calls `verify_messages` on Axelar (internal) gateway contract for eth
3. Axelar:eth gateway calls `verify_messages` on voting verifier, which starts ETH verifier voting via ampd
4. once quorum of votes are cast for the message, an event is emitted.
5. another axelar-specific relayer "Listener" listens for this event to call `route_messages` on Axelar:eth gateway.
6. chain’s Axelar gateway passes the message to the Amplifier router, which then passes it on to Axelar:TN gateway.
7. Listener calls `construct_proof` to start the process of creating a signed batch that can be relayed back to eth as well as pass the now-outbound message from the Axelar:TN gateway to the prover.
8. prover starts a signing session with the multisig contract by emitting event
9. noticing the event, TN verifiers participate in the signing session via ampd
10. once quorum signatures are submitted, Includer uses the fully signed proof from the prover and relays the proof to TN to execute transactions on TN.

The Subscriber: the Subscriber’s job is to guarantee that every protocol event on the Amplifier chain is detected and successfully published to the Amplifier API. The relayer detects outgoing GMP messages from the chain to the AVM and publishes them to the GMP API so that they can be verified, routed, signed, and delivered to the destination chain.

Subscriber spec:

- subscribe to external eth gateway
- filter for `ContractCall(address indexed sender, string destinationChain, string destinationContractAddress, bytes32 indexed payloadHash, bytes payload)`
- ensure target function is `execute(bytes32 commandId, string calldata sourceChain, string calldatasourceAddress, bytes calldata payload)` ?
- publish to amplifier GMP API using CallEvent, obtain confirmation response

The Includer: the Includer’s job is to guarantee that some payload (task) gets included in a transaction in a block on the Amplifier chain. The relayer receives incoming GMP messages from the AVM to the chain and executes them by writing the transaction payloads to a block on the Amplifier chain.

Includer spec:

- poll amplifier Task API for new tasks
- check whether new tasks are already executed (ie by another includer)
- translate task payload into transaction
- sign transaction and publish to TN (via RPC or direct-to-node?)
- monitor transaction & adjust gas params if necessary
- must push latest task ID to some persistent storage (in case where includer goes offline, taskID has been consumed at TaskAPI)

Events Endpoint `POST /chains/{chain}/events`:
In this endpoint, events are published that indicate completed actions for the cross-chain messaging process. Developers can use this endpoint to submit the completion of new actions (e.g., that an new contract call was made, or a message was approved).

Tasks Endpoint `GET /chains/{chain}/tasks`:
This endpoint returns tasks associated with the cross-chain messaging protocol. Each one of these tasks indicates an operation that needs to take place in order to proceed with the process of a GMP call. Developers can use this endpoint to monitor and react to various tasks (e.g., trigger an execution, or a refund).

manual flow:
https://docs.axelar.dev/dev/amplifier/chain-integration/relay-messages/manual/
