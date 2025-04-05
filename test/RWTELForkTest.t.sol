// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { IDeploy } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IDeploy.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { IInterchainTokenService } from "@axelar-network/interchain-token-service/contracts/interfaces/IInterchainTokenService.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/utils/Create3Utils.sol";
import { ITS } from "../deployments/Deployments.sol";
import { HarnessCreate3FixedAddressForITS, ITSTestHelper } from "./ITS/ITSTestHelper.sol";

contract RWTELForkTest is Test, ITSTestHelper {
    Deployments deployments;
    address admin;

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    address telDistributor;
    address user;
    string sourceChain;
    string sourceAddress;
    string destChain;
    address destinationAddress;
    string axelarHubAddress;
    string name;
    string symbol;
    uint8 decimals;
    uint256 amount;
    bytes payload;
    bytes wrappedPayload;
    string messageId;
    Message[] messages;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        name = "Telcoin";
        symbol = "TEL";
        decimals = 2;
        amount = 100; // 1 ERC20 tel

        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        tnFork = vm.createFork(TN_RPC_URL);
    }

    /// @notice Test to ensure TN genesis rwTEL and rwTELTokenManager precompiles match Ethereum ITS's canonical addresses
    /// using a simulated call to `deployRemoteCanonicalInterchainToken` (obviated in production by Telcoin-Network genesis)
    /// @notice Ensures precompiles for RWTEL + its TokenManager match those expected (& otherwise produced) by ITS
    function test_e2eDevnet_deployRemoteCanonicalInterchainToken_RWTEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (bytes32 returnedInterchainTokenSalt, bytes32 returnedInterchainTokenId, TokenManager returnedTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);

        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        payload =
            abi.encode(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, returnedInterchainTokenId, name, symbol, decimals, "");
        wrappedPayload = abi.encode(MESSAGE_TYPE_SEND_TO_HUB, destinationChain, payload);
        axelarHubAddress = sepoliaITS.trustedAddress(ITS_HUB_CHAIN_NAME);
        vm.expectEmit(true, true, true, true);
        emit ContractCall(
            address(sepoliaITS), ITS_HUB_CHAIN_NAME, axelarHubAddress, keccak256(wrappedPayload), wrappedPayload
        );
        /// @notice This deployment and all following steps are obviated by genesis precompiles and must
        /// be skipped, because ITS + RWTEL are created at TN genesis, and it results in `RWTEL::decimals == 2`
        bytes32 remoteCanonicalTokenId =
            sepoliaITF.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);
        assertEq(remoteCanonicalTokenId, returnedInterchainTokenId);

        /**
         * @dev Verifier Action: Vote on GMP Message Event Validity via Ampd
         * GMP message reaches Axelar Network Voting Verifier contract, where a "verifier" (ampd client ECDSA key)
         * signs and submits signatures ie "votes" or "proofs" via RPC. Verifiers are also known as `WeightedSigners`
         * @notice Devnet config uses `admin` as a single signer with weight and threshold == 1
         */

        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(deployments.its, deployments.admin, deployments.sepoliaTEL, deployments.wTEL, deployments.rwTELImpl, deployments.rwTEL, deployments.rwTELTokenManager);

        // assert genesis instantiations match ITS expectations
        assertEq(address(returnedTELTokenManager), rwTEL.tokenManagerAddress());
        assertEq(its.interchainTokenAddress(returnedInterchainTokenId), deployments.rwTEL);
        assertEq(address(returnedTELTokenManager), deployments.rwTELTokenManager);
        assertEq(returnedInterchainTokenSalt, canonicalInterchainTokenSalt);
        assertEq(returnedInterchainTokenId, canonicalInterchainTokenId);
        assertEq(address(returnedTELTokenManager), address(canonicalTELTokenManager));

        messageId = "42";
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        sourceAddress = LibString.toHexString(address(sepoliaITS));
        destinationAddress = address(its);
        Message memory message = _craftITSMessage(messageId, sourceChain, sourceAddress, destinationAddress, payload);
        messages.push(message);

        (WeightedSigners memory weightedSigners, bytes32 approveMessagesHash) =
            _getWeightedSignersAndApproveMessagesHash(messages, gateway);
        // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
        uint256 ampdVerifierPK = vm.envUint("ADMIN_PK"); //todo: use ampd
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ampdVerifierPK, approveMessagesHash);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);
        Proof memory proof = Proof(weightedSigners, signatures);

        /**
         * @dev Relayer Action: Approve GMP Message on Destination Gateway
         * Includer polls GMP API for the message processed by Axelar Network verifiers, writes to TN gateway in TX
         * Once settled, GMP message has been successfully sent across chains (bridged) and awaits execution
         */
        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddress, destinationAddress, keccak256(payload));
        gateway.approveMessages(messages, proof);

        /**
         * @dev Relayer Action: Execute GMP Message (`ContractCall`) on RWTEL Module
         * Includer executes GMP messages that have been written to the TN gateway in previous step
         * this tx calls RWTEL module which mints the TEL tokens and delivers them to recipient
         */

        bytes memory alreadyDeployed = abi.encodePacked(IDeploy.AlreadyDeployed.selector);
        bytes memory rwtelCollision = abi.encodeWithSelector(IInterchainTokenService.InterchainTokenDeploymentFailed.selector, alreadyDeployed);
        vm.expectRevert(rwtelCollision);
        its.execute(commandId, sourceChain, sourceAddress, payload);

        // wipe genesis deployment to prevent revert on token deployment and reach revert on token manager deploy 
        vm.etch(address(rwTEL), '');
        bytes memory tokenManagerCollision = abi.encodeWithSelector(IInterchainTokenService.TokenManagerDeploymentFailed.selector, alreadyDeployed);
        vm.expectRevert(tokenManagerCollision);
        its.execute(commandId, sourceChain, sourceAddress, payload);
    }

    // rwtel asserts
    // bytes32 rwtelTokenId = rwTEL.interchainTokenId();
    // assertEq(rwtelTokenId, sepoliaITS.interchainTokenId(address(0x0), returnedInterchainTokenSalt));
    // assertEq(rwtelTokenId, sepoliaITF.returnedInterchainTokenId(canonicalTEL));
    // assertEq(rwtelTokenId, returnedInterchainTokenId);
    // assertEq(rwtelTokenId, tmDeploySaltIsTELInterchainTokenId);
    // assertEq(rwTEL.tokenManagerCreate3Salt(), tmDeploySaltIsTELInterchainTokenId);
    // assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), returnedInterchainTokenSalt);
    // assertEq(rwTEL.canonicalInterchainTokenDeploySalt(),
    // sepoliaITF.canonicalInterchainTokenDeploySalt(canonicalTEL));
    // assertEq(rwTEL.tokenManagerAddress(), address(returnedTELTokenManager));
    // assertEq(rwtelTokenId, ITFactory.interchainTokenId(address(0x0), returnedInterchainTokenSalt));
    //     assertEq(rwtelTokenId, ITFactory.returnedInterchainTokenId(address(canonicalTEL)));

    //todo: asserts for devnet fork test & script
    // assertEq(remoteRwtelInterchainToken, expectedInterchainToken);
    // ITokenManager returnedTELTokenManager = its.deployedTokenManager(returnedInterchainTokenId);
    // assertEq(remoteRwtelTokenManager, address(returnedTELTokenManager));
    // assertEq(remoteRwtelTokenManager, telTokenManagerAddress);
    // assertEq(rwtelExpectedInterchainToken, address(rwTEL)); //todo: genesis assertion
    // assertEq(rwtelExpectedTokenManager, address(rwTELTokenManager)); //todo: genesis assertion

    //     // function test_tn_rwtelInterchainTransfer_RWTEL() public {}
    //     // function test_tn_rwtelTransmitInterchainTransfer_RWTEL() public {
    //     // function test_tn_itsInterchainTransfer_RWTEL() public {}
    //     // function test_tn_itsTransmitInterchainTransfer_RWTEL() public {
    //     // function test_tn_giveToken_RWTEL() public {
    //     //    tokenhandler.giveToken() directly
    //     // }
    //     // function test_tn_takeToken_RWTEL() public {}
    //     //    tokenhandler.takeToken() directly
    //     // }

    // function test_e2e_bridgeSimulation_sepoliaToTN() public {
    //         /// @dev This test is skipped because it relies on signing with a local key
    //         /// and to save on RPC calls. Remove to unskip
    //         vm.skip(true); //todo

    //         setUpForkConfig();

    //         sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
    //         vm.selectFork(sepoliaFork);

    //         sourceChain = "ethereum-sepolia";
    //         sourceAddress = LibString.toHexString(uint256(uint160(address(sepoliaGateway))), 20);
    //         destChain = "telcoin-network";
    //         destAddress = LibString.toHexString(uint256(uint160(address(tnRWTEL))), 20);

    //         vm.startPrank(user);
    //         // user must have tokens and approve gateway
    //         sepoliaTel.approve(address(sepoliaGateway), amount);

    //         // subscriber will monitor `ContractCall` events
    //         vm.expectEmit(true, true, true, true);
    //         emit ContractCall(user, destChain, destAddress, payloadHash, payload);
    //         sepoliaGateway.callContract(destChain, destAddress, payload);
    //         vm.stopPrank();

    //         /**
    //          * @dev Relayer Action: Monitor Source Gateway for GMP Message Event Emission
    //          * subscriber picks up event + forwards to GMP API where it is processed by TN verifier
    //          */
    //         tnFork = vm.createFork(TN_RPC_URL);
    //         vm.selectFork(tnFork);

    //         messageId = "42";
    //         messages.push(Message(sourceChain, messageId, sourceAddress, address(tnRWTEL), payloadHash));
    //         // proof must be signed keccak hash of abi encoded `CommandType.ApproveMessages` & message array
    //         bytes32 dataHash = keccak256(abi.encode(CommandType.ApproveMessages, messages));
    //         // `domainSeparator` and `signersHash` for the current epoch are queriable on gateway
    //         bytes32 ethSignPrefixedMsgHash = keccak256(
    //             bytes.concat(
    //                 "\x19Ethereum Signed Message:\n96",
    //                 tnGateway.domainSeparator(),
    //                 tnGateway.signersHashByEpoch(tnGateway.epoch()),
    //                 dataHash
    //             )
    //         );

    //         // TN gateway currently uses a single signer of `admin` with weight 1
    //         WeightedSigner[] memory signers = new WeightedSigner[](1);
    //         signers[0] = WeightedSigner(admin, 1);
    //         // signer set `nonce == bytes32(0)` and for a single signer, `threshold == 1`
    //         WeightedSigners memory weightedSigners = WeightedSigners(signers, 1, bytes32(0x0));
    //         // Axelar gateway signer proofs are ECDSA signatures of bridge message `eth_sign` hash
    //         (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("ADMIN_PK"), ethSignPrefixedMsgHash);
    //         bytes[] memory signatures = new bytes[](1);
    //         signatures[0] = abi.encodePacked(r, s, v);
    //         Proof memory proof = Proof(weightedSigners, signatures);

    //         bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
    //         vm.expectEmit(true, true, true, true);
    //         emit MessageApproved(commandId, sourceChain, messageId, sourceAddress, address(tnRWTEL), payloadHash);
    //         vm.prank(admin);
    //         tnGateway.approveMessages(messages, proof);

    //         uint256 userBalBefore = user.balance;

    //         vm.expectEmit(true, true, true, true);
    //         emit MessageExecuted(commandId);
    //         vm.prank(admin);
    //         // tnRWTEL.executeWithInterchainToken(
    //         //     commandId, sourceChain, bytes(sourceAddress), payload, tokenId, token, amount
    //         // );

    //         // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
    //         assertEq(user.balance, userBalBefore + amount);
    //     }

    // function test_e2e_bridgeSimulation_sepoliaToTN() public {
    //         /// @dev This test is skipped because it relies on signing with a local key
    //         /// and to save on RPC calls. Remove to unskip
    //         // vm.skip(true); //todo

    //         setUpForkConfig();

    //         tnFork = vm.createFork(TN_RPC_URL);
    //         vm.selectFork(tnFork);

    //         vm.deal(user, amount + 100);
    //         sourceChain = "telcoin-network";
    //         sourceAddress = LibString.toHexString(uint256(uint160(address(tnGateway))), 20);
    //         destChain = "ethereum-sepolia";
    //         // Axelar Ethereum-Sepolia gateway predates AxelarExecutable contract; it contains execution logic
    //         destAddress = LibString.toHexString(uint256(uint160(address(sepoliaGateway))), 20);

    //         vm.startPrank(user);
    //         // wrap amount to wTEL and then to rwTEL, which initiates `recoverableWindow`
    //         tnWTEL.deposit{ value: amount }();
    //         tnWTEL.approve(address(tnRWTEL), amount);
    //         tnRWTEL.wrap(amount);

    //         // construct payload
    //         messageId = "42";
    //         bytes32[] memory commandIds = new bytes32[](1);
    //         bytes32 commandId = tnGateway.messageToCommandId(sourceChain, messageId);
    //         commandIds[0] = commandId;
    //         string[] memory commands = new string[](1);
    //         commands[0] = "mintToken";
    //         bytes[] memory params = new bytes[](1);
    //         bytes memory mintTokenParams = abi.encode(symbol, user, amount);
    //         params[0] = mintTokenParams;
    //         bytes memory data = abi.encode(11_155_111, commandIds, commands, params);
    //         bytes memory proof = "";
    //         payload = abi.encode(data, proof);

    //         // elapse time
    //         vm.warp(block.timestamp + recoverableWindow_);

    //         vm.expectEmit();
    //         emit ContractCall(user, destChain, destAddress, keccak256(payload), payload);
    //         tnGateway.callContract(destChain, destAddress, payload);

    //         // sepolia side
    //         sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
    //         vm.selectFork(sepoliaFork);

    //         // sepoliaGateway.execute(payload);

    //todo: token bridge test asserts, move natspec comments
    // uint256 userBalBefore = user.balance;
    // sepolia TEL ERC20 has been bridged and delivered to user as native TEL
    // assertEq(user.balance, userBalBefore + amount); //todo: token bridge test
    // }
    //     }
}
