// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
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
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../../src/WTEL.sol";
import { RWTEL } from "../../src/RWTEL.sol";
import { ExtCall } from "../../src/interfaces/IRWTEL.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../../deployments/utils/Create3Utils.sol";
import { ITSConfig } from "../../deployments/utils/ITSConfig.sol";
import { HarnessCreate3FixedAddressForITS, ITSTestHelper } from "./ITSTestHelper.sol";

contract InterchainTokenServiceForkTest is Test, ITSTestHelper {
    // canonical chain config (sepolia or ethereum)
    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL
    TokenManager canonicalTELTokenManager;

    Deployments deployments;
    address admin; // note: possesses all permissions on devnet only

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

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

    /// @dev Test the flow for registering a token with ITS hub + deploying its manager
    /// @notice In prod, these calls must be performed on Ethereum prior to TN genesis
    function test_sepoliaFork_registerCanonicalInterchainToken() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );

        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        uint256 gasValue = 100; // dummy gas value just specified for multicalls
        (canonicalInterchainSalt, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);

        vm.expectRevert();
        canonicalTELTokenManager.proposeOperatorship(admin);
        vm.expectRevert();
        canonicalTELTokenManager.transferOperatorship(admin);
        vm.expectRevert();
        canonicalTELTokenManager.acceptOperatorship(admin);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowLimiter(admin);
        vm.expectRevert();
        canonicalTELTokenManager.removeFlowLimiter(admin);
        uint256 dummyAmt = 1;
        vm.expectRevert();
        canonicalTELTokenManager.setFlowLimit(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowIn(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowOut(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.mintToken(address(canonicalTEL), address(admin), dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.burnToken(address(canonicalTEL), address(admin), dummyAmt);

        // `BaseProxy::setup()` doesn't revert but does nothing if invoked outside of `TokenManagerProxy` constructor
        canonicalTELTokenManager.setup(abi.encode(address(0), address(0x42)));
        assertFalse(canonicalTELTokenManager.isOperator(address(0x42)));

        // check expected create3 address for canonicalTEL TokenManager using harness & restore
        bytes memory restoreCodeITS = address(sepoliaITS).code;
        vm.etch(address(sepoliaITS), type(HarnessCreate3FixedAddressForITS).runtimeCode);
        HarnessCreate3FixedAddressForITS itsCreate3 = HarnessCreate3FixedAddressForITS(address(sepoliaITS));
        // note to deploy TokenManagers ITS uses a different create3 salt schema that 'wraps' the token's canonical
        // deploy salt
        bytes32 tmDeploySaltIsTELInterchainTokenId =
            keccak256(abi.encode(keccak256("its-interchain-token-id"), address(0x0), canonicalInterchainSalt));
        assertEq(itsCreate3.create3Address(tmDeploySaltIsTELInterchainTokenId), address(canonicalTELTokenManager));
        vm.etch(address(sepoliaITS), restoreCodeITS);

        // ITS asserts post registration && deployed canonicalTELTokenManager
        address canonicalTELTokenManagerExpected = sepoliaITS.tokenManagerAddress(canonicalInterchainTokenId);
        assertEq(address(canonicalTELTokenManager), canonicalTELTokenManagerExpected);
        assertTrue(canonicalTELTokenManagerExpected.code.length > 0);
        assertEq(
            address(sepoliaITS.deployedTokenManager(canonicalInterchainTokenId)), address(canonicalTELTokenManager)
        );
        assertEq(sepoliaITS.registeredTokenAddress(canonicalInterchainTokenId), canonicalTEL);

        // canonicalTEL TokenManager asserts
        assertEq(canonicalTELTokenManager.contractId(), keccak256("token-manager"));
        assertEq(canonicalTELTokenManager.interchainTokenId(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(canonicalTELTokenManager.implementationType(), uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(canonicalTELTokenManager.tokenAddress(), address(canonicalTEL));
        assertEq(canonicalTELTokenManager.isOperator(address(0x0)), true);
        assertEq(canonicalTELTokenManager.isOperator(address(sepoliaITS)), true);
        assertEq(canonicalTELTokenManager.isFlowLimiter(address(sepoliaITS)), true);
        assertEq(canonicalTELTokenManager.flowLimit(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowInAmount(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowOutAmount(), 0); // set by ITS
        bytes memory ethTMSetupParams = abi.encode(bytes(""), canonicalTEL);
        assertEq(canonicalTELTokenManager.getTokenAddressFromParams(ethTMSetupParams), canonicalTEL);
        (uint256 implementationType, address tokenAddress) =
            TokenManagerProxy(payable(address(canonicalTELTokenManager))).getImplementationTypeAndTokenAddress();
        assertEq(implementationType, uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(tokenAddress, canonicalTEL);
    }

    /// @dev TN-inbound ITS bridge tests

    function test_sepoliaFork_itsInterchainTransfer_TEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // give gas funds to user and pre-approve ITS to spend its TEL
        vm.deal(user, gasValue);
        vm.prank(user);
        IERC20(canonicalTEL).approve(address(sepoliaITS), amount);

        bytes memory destAddressBytes = AddressBytes.toBytes(user);
        uint256 srcBalBefore = IERC20(canonicalTEL).balanceOf(user);
        uint256 destBalBefore = IERC20(canonicalTEL).balanceOf(address(sepoliaITS));
        vm.prank(user);
        sepoliaITS.interchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, destinationChain, destAddressBytes, amount, "", gasValue
        );

        assertEq(IERC20(canonicalTEL).balanceOf(user), srcBalBefore - amount);
        assertEq(IERC20(canonicalTEL).balanceOf(address(canonicalTELTokenManager)), destBalBefore + amount);
    }

    function test_sepoliaFork_itsTransmitInterchainTransfer_TEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig(
            deployments.sepoliaTEL, deployments.its.InterchainTokenService, deployments.its.InterchainTokenFactory
        );

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // give gas funds to user and pre-approve ITS to spend its TEL
        vm.deal(user, gasValue);
        vm.prank(user);
        IERC20(canonicalTEL).approve(address(sepoliaITS), amount);

        bytes memory destAddressBytes = AddressBytes.toBytes(user);
        uint256 srcBalBefore = IERC20(canonicalTEL).balanceOf(user);
        uint256 destBalBefore = IERC20(canonicalTEL).balanceOf(address(sepoliaITS));

        // note: direct calls to `ITS::transmitInterchainTransfer()` can only be called by the token
        // thus it is disabled on Ethereum since ethTEL doesn't have this function
        vm.prank(user);
        vm.expectRevert();
        sepoliaITS.transmitInterchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, user, destinationChain, destAddressBytes, amount, ""
        );

        assertEq(IERC20(canonicalTEL).balanceOf(user), srcBalBefore);
        assertEq(IERC20(canonicalTEL).balanceOf(address(canonicalTELTokenManager)), destBalBefore);
    }

    // todo: ensure payload doesn't need to be hub-wrapped for approve, execute
    function test_tnFork_approveMessages() public {
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(deployments.its, deployments.admin, deployments.sepoliaTEL, deployments.wTEL, deployments.rwTELImpl, deployments.rwTEL);

        messageId = "42";
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        sourceAddress = LibString.toHexString(deployments.its.InterchainTokenService);
        // note: for interchain transfers, Message's `destinationAddress = its` and payload's `recipient = user`
        destinationAddress = address(its);
        address recipient = user;
        payload = abi.encode(
            MESSAGE_TYPE_INTERCHAIN_TRANSFER,
            canonicalInterchainTokenId,
            sourceAddress,
            AddressBytes.toBytes(recipient),
            amount,
            ""
        );
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

        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddress, destinationAddress, keccak256(payload));
        gateway.approveMessages(messages, proof);

        assertTrue(
            gateway.isMessageApproved(sourceChain, messageId, sourceAddress, destinationAddress, keccak256(payload))
        );
    }

    // todo: ensure payload doesn't need to be hub-wrapped for approve, execute
    function test_tnFork_execute() public {
        vm.selectFork(tnFork);
        setUp_tnFork_devnetConfig_genesis(deployments.its, deployments.admin, deployments.sepoliaTEL, deployments.wTEL, deployments.rwTELImpl, deployments.rwTEL);
        //todo: etch bytecode & storage onto devnet ITS

        messageId = "42";
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        sourceAddress = LibString.toHexString(deployments.its.InterchainTokenService);
        // note: for interchain transfers, Message's `destinationAddress = its` and payload's `recipient = user`
        destinationAddress = address(its);
        address recipient = user;
        payload = abi.encode(
            MESSAGE_TYPE_INTERCHAIN_TRANSFER,
            canonicalInterchainTokenId,
            sourceAddress,
            AddressBytes.toBytes(recipient),
            amount,
            ""
        );
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

        bytes32 commandId = gateway.messageToCommandId(sourceChain, messageId);
        vm.expectEmit(true, true, true, true);
        emit MessageApproved(commandId, sourceChain, messageId, sourceAddress, destinationAddress, keccak256(payload));
        gateway.approveMessages(messages, proof);

        uint256 userBalBefore = user.balance;

        vm.expectEmit(true, true, true, true);
        emit MessageExecuted(commandId);
        its.execute(commandId, sourceChain, sourceAddress, payload);

        assertEq(user.balance, userBalBefore + amount);
    }

    /// @dev TN-outbound ITS bridge tests

    // function test_tnFork_itsInterchainTransfer_RWTEL() public {}
    // function test_tnFork_itsTransmitInterchainTransfer_RWTEL() public {

    // function test_sepoliaFork_approveMessages() public {

    // function test_sepoliaFork_execute() public {

    // its.contractCallValue(); // todo: decimals handling?
    //todo: fuzz tests for rwTEL, TEL bridging, rwteltest.t.sol
    //todo: fork tests for TEL bridging
    //todo: incorporate RWTEL contracts to TN protocol on rust side
    //todo: remove ExtCall
    //todo: update readme, npm instructions

    //todo: non-TEL ERC20 bridging tests
    // function test_ERC20_interchainToken() public {
    //     // //todo: Non-TEL ERC20 InterchainToken asserts
    //     // assertEq(interchainToken.interchainTokenService(), address(its));
    //     // assertTrue(interchainToken.isMinter(address(its)));
    //     // assertEq(interchainToken.totalSupply(), totalSupply);
    //     // assertEq(interchainToken.balanceOf(address(rwTEL)), bal);
    //     // assertEq(interchainToken.nameHash(), nameHash);
    //     // assertEq(interchainToken.DOMAIN_SEPARATOR(), itDomainSeparator);
    // }
}
