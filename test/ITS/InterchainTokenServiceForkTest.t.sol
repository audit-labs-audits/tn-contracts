// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
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
import { ITSUtilsFork } from "../../deployments/utils/ITSUtilsFork.sol";
import "./ITSMocks.sol";

contract InterchainTokenServiceForkTest is Test, ITSUtilsFork {
    // canonical chain config (sepolia or ethereum)
    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL
    TokenManager canonicalTELTokenManager;

    // Sepolia contracts
    IERC20 sepoliaTEL;
    InterchainTokenService sepoliaITS;
    InterchainTokenFactory sepoliaITF;
    IAxelarGateway sepoliaGateway;

    //todo: Ethereum contracts

    // Telcoin Network contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;
    Create3Deployer create3;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy
    TokenManager canonicalRWTELTokenManager;

    Deployments deployments;
    address admin;
    address deployerEOA; // note: devnet only
    address rwtelOwner; // note: devnet only

    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string TN_RPC_URL = vm.envString("TN_RPC_URL");
    uint256 sepoliaFork;
    uint256 tnFork;

    address user;
    string sourceChain;
    string sourceAddress;
    string destChain;
    address destinationAddress;
    string name;
    string symbol;
    uint8 decimals;
    uint256 amount;
    // bytes extCallData; //todo delete
    bytes payload;
    string messageId;
    Message[] messages;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        deployerEOA = admin;
        user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
        name = "Telcoin";
        symbol = "TEL";
        decimals = 2;
        amount = 100; // 1 ERC20 tel

        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);
        tnFork = vm.createFork(TN_RPC_URL);
    }

    function setUp_sepoliaFork_devnetConfig() internal {
        sepoliaTEL = IERC20(deployments.sepoliaTEL);
        sepoliaITS = InterchainTokenService(deployments.its.InterchainTokenService);
        sepoliaITF = InterchainTokenFactory(deployments.its.InterchainTokenFactory);
        sepoliaGateway = IAxelarGateway(DEVNET_SEPOLIA_GATEWAY);
        canonicalTEL = address(sepoliaTEL);
    }


    /// TODO: Until testnet is restarted with genesis precompiles, this function deploys ITS via create3
    /// @notice For devnet, a developer admin address serves all permissioned roles
    function setUp_tnFork_DevnetConfig() internal {
        vm.selectFork(tnFork);

        wTEL = WTEL(payable(deployments.wTEL));
        // todo: uncomment this section after testnet restart with genesis precompiles
        // gatewayImpl = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGatewayImpl);
        // gateway = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGateway);
        // tokenManagerDeployer = TokenManagerDeployer(deployments.its.TokenManagerDeployer);
        // interchainTokenImpl = InterchainToken(deployments.its.InterchainTokenImpl);
        // itDeployer = InterchainTokenDeployer(deployments.its.InterchainTokenDeployer);
        // tokenManagerImpl = TokenManager(deployments.its.TokenManagerImpl);
        // tokenHandler = TokenHandler(deployments.its.TokenHandler);
        // gasServiceImpl = AxelarGasService(deployments.its.GasServiceImpl);
        // gasService = AxelarGasService(deployments.its.GasService);
        // gatewayCaller = GatewayCaller(deployments.its.GatewayCaller);
        // itsImpl = InterchainTokenService(deployments.its.InterchainTokenServiceImpl);
        // its = InterchainTokenService(deployments.its.InterchainTokenService);
        // itFactoryImpl = InterchainTokenFactory(deployments.its.InterchainTokenFactoryImpl);
        // itFactory = InterchainTokenFactory(deployments.its.InterchainTokenFactory);
        // rwTELImpl = RWTEL(deployments.rwTELImpl);
        // rwTEL = RWTEL(deployments.rwTEL);


        // todo: replace this section after testnet restart with genesis precompiles
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        // ITS address must be derived w/ sender + salt pre-deploy, for TokenManager && InterchainToken constructors
        address expectedITS = create3.deployedAddress("", deployerEOA, salts.itsSalt);
        // must precalculate ITF proxy to avoid `ITS::constructor()` revert
        address expectedITF = create3.deployedAddress("", deployerEOA, salts.itfSalt);
        _setUpDevnetConfig(admin, address(sepoliaTEL), address(wTEL), expectedITS, expectedITF);

        vm.startPrank(deployerEOA);
        gatewayImpl = create3DeployAxelarAmplifierGatewayImpl(create3);
        gateway = create3DeployAxelarAmplifierGateway(create3, address(gatewayImpl));
        tokenManagerDeployer = create3DeployTokenManagerDeployer(create3);
        interchainTokenImpl = create3DeployInterchainTokenImpl(create3);
        itDeployer = create3DeployInterchainTokenDeployer(create3, address(interchainTokenImpl));
        tokenManagerImpl = create3DeployTokenManagerImpl(create3);
        tokenHandler = create3DeployTokenHandler(create3);
        gasServiceImpl = create3DeployAxelarGasServiceImpl(create3);
        gasService = create3DeployAxelarGasService(create3, address(gasServiceImpl));
        gatewayCaller = create3DeployGatewayCaller(create3, address(gateway), address(gasService));
        itsImpl = create3DeployITSImpl(
            create3,
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            address(tokenManagerImpl),
            address(tokenHandler),
            address(gatewayCaller)
        );
        its = create3DeployITS(create3, address(itsImpl));
        itFactoryImpl = create3DeployITFImpl(create3, address(its));
        itFactory = create3DeployITF(create3, address(itFactoryImpl));
        rwTELImpl = create3DeployRWTELImpl(create3, address(its));
        rwTEL = create3DeployRWTEL(create3, address(rwTELImpl));

        rwtelOwner = admin;
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
        // todo: rwTEL will be seeded with TEL total supply as genesis precompile
        uint256 nativeTELTotalSupply = 100_000_000_000e18;
        vm.deal(address(rwTEL), nativeTELTotalSupply); // for now, seed directly
        
        vm.stopPrank();

        assertEq(address(its), precalculatedITS);
        assertEq(address(itFactory), precalculatedITFactory);
    }


    /// @dev Test the flow for registering a token with ITS hub + deploying its manager
    /// @notice In prod, these calls must be performed on Ethereum prior to TN genesis
    function test_sepoliaFork_registerCanonicalInterchainToken() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig();

        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        uint256 gasValue = 100; // dummy gas value just specified for multicalls
        (canonicalInterchainSalt, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);

        vm.expectRevert();
        canonicalTELTokenManager.proposeOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.transferOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.acceptOperatorship(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowLimiter(deployerEOA);
        vm.expectRevert();
        canonicalTELTokenManager.removeFlowLimiter(deployerEOA);
        uint256 dummyAmt = 1;
        vm.expectRevert();
        canonicalTELTokenManager.setFlowLimit(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowIn(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.addFlowOut(dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.mintToken(address(canonicalTEL), address(deployerEOA), dummyAmt);
        vm.expectRevert();
        canonicalTELTokenManager.burnToken(address(canonicalTEL), address(deployerEOA), dummyAmt);

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
        assertEq(address(sepoliaITS.deployedTokenManager(canonicalInterchainTokenId)), address(canonicalTELTokenManager));
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
        (uint256 implementationType, address tokenAddress) = TokenManagerProxy(payable(address(canonicalTELTokenManager))).getImplementationTypeAndTokenAddress();
        assertEq(implementationType, uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(tokenAddress, canonicalTEL);
    }

    /// @notice `deployRemoteCanonicalInterchainToken` will route a `MESSAGE_TYPE_LINK_TOKEN` through ITS hub
    /// that is guaranteed to revert trying to deploy on preexisting genesis precompiles, thus it should be skipped
    /// @notice Ensures precompiles for RWTEL + its TokenManager match those expected (& otherwise produced) by ITS 
    function test_e2e_deployRemoteCanonicalInterchainToken_simulateOnly() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig();

        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, sepoliaITS, sepoliaITF, gasValue);
        
        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        /// @notice This `deployRemoteCanonicalInterchainToken()` step is obviated by genesis precompiles and must
        /// be skipped, because ITS + RWTEL are created at TN genesis, and it results in `RWTEL::decimals == 2`
        bytes32 remoteCanonicalTokenId =
            sepoliaITF.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);
        assertEq(remoteCanonicalTokenId, canonicalInterchainTokenId);

        /**
         * @dev Verifier Action: Vote on GMP Message Event Validity via Ampd
         * GMP message reaches Axelar Network Voting Verifier contract, where a "verifier" (ampd client ECDSA key)
         * signs and submits signatures ie "votes" or "proofs" via RPC. Verifiers are also known as `WeightedSigners`
         * @notice Devnet config uses `admin` as a single signer with weight and threshold == 1
         */
        
        vm.selectFork(tnFork);
        setUp_tnFork_DevnetConfig();

        messageId = "42";
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        sourceAddress = LibString.toHexString(address(sepoliaITS));
        destinationAddress = address(its);
        payload = abi.encode(MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN, canonicalInterchainTokenId, name, symbol, decimals, '');
        Message memory message = _craftITSMessage(messageId, sourceChain, sourceAddress, destinationAddress, payload);
        messages.push(message);

        (WeightedSigners memory weightedSigners, bytes32 approveMessagesHash)= _getWeightedSignersAndApproveMessagesHash(messages, gateway);
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

        vm.expectEmit(true, true, true, true);
        emit MessageExecuted(commandId);
        its.execute(commandId, sourceChain, sourceAddress, payload);

        //todo: etch bytecode & storage onto devnet ITS
        //todo: write rwTEL to ITS create3 `interchainTokenAddress` and rwTELTokenManager to ITS create3 canonicalTElTokenManager
        // assertEq(0x8579FABCc18dcEaD408d87048eDB8BC5a5f3E9B6, interchainTokenAddress, rwtel)
        // assertEq(0x4542A3a5401733FA778B31d4c46539D4Bd0830DE(notetched), canonicalTELTokenManager, rwTELTokenManager)

        // assertEq(its.interchainTokenAddress(canonicalInterchainTokenId), address(rwTEL));
    }

    // its.contractCallValue(); // todo: decimals handling?


        //todo: test flow of incoming deploy RWTEL & tokenManager message
        // assert incoming rwtel & token manager that would be deployed match deployments.rwTEL/manager

        // rwtel asserts
        // bytes32 rwtelTokenId = rwTEL.interchainTokenId();
        // assertEq(rwtelTokenId, sepoliaITS.interchainTokenId(address(0x0), canonicalInterchainSalt));
        // assertEq(rwtelTokenId, sepoliaITF.canonicalInterchainTokenId(canonicalTEL));
        // assertEq(rwtelTokenId, canonicalInterchainTokenId);
        // assertEq(rwtelTokenId, tmDeploySaltIsTELInterchainTokenId);
        // assertEq(rwTEL.tokenManagerCreate3Salt(), tmDeploySaltIsTELInterchainTokenId);
        // assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), canonicalInterchainSalt);
        // assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), sepoliaITF.canonicalInterchainTokenDeploySalt(canonicalTEL));
        // assertEq(rwTEL.tokenManagerAddress(), address(canonicalTELTokenManager));
        // assertEq(rwtelTokenId, ITFactory.interchainTokenId(address(0x0), canonicalInterchainSalt));
        //     assertEq(rwtelTokenId, ITFactory.canonicalInterchainTokenId(address(canonicalTEL)));

    //todo: asserts for devnet fork test & script
    // assertEq(remoteRwtelInterchainToken, expectedInterchainToken);
    // ITokenManager canonicalTELTokenManager = its.deployedTokenManager(canonicalInterchainTokenId);
    // assertEq(remoteRwtelTokenManager, address(canonicalTELTokenManager));
    // assertEq(remoteRwtelTokenManager, telTokenManagerAddress);
    // assertEq(rwtelExpectedInterchainToken, address(rwTEL)); //todo: genesis assertion
    // assertEq(rwtelExpectedTokenManager, address(rwTELTokenManager)); //todo: genesis assertion


    /// @dev Inbound ITS bridge tests

    function test_sepoliaFork_itsInterchainTransfer_TEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig();

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
        MockTEL(canonicalTEL).approve(address(sepoliaITS), amount);

        bytes memory destAddressBytes = AddressBytes.toBytes(user);
        uint256 srcBalBefore = MockTEL(canonicalTEL).balanceOf(user);
        uint256 destBalBefore = MockTEL(canonicalTEL).balanceOf(address(sepoliaITS));
        vm.prank(user);
        sepoliaITS.interchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, destinationChain, destAddressBytes, amount, "", gasValue
        );

        assertEq(MockTEL(canonicalTEL).balanceOf(user), srcBalBefore - amount);
        assertEq(MockTEL(canonicalTEL).balanceOf(address(canonicalTELTokenManager)), destBalBefore + amount);
    }

    function test_sepoliaFork_itsTransmitInterchainTransfer_TEL() public {
        vm.selectFork(sepoliaFork);
        setUp_sepoliaFork_devnetConfig();

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
        MockTEL(canonicalTEL).approve(address(sepoliaITS), amount);

        bytes memory destAddressBytes = AddressBytes.toBytes(user);
        uint256 srcBalBefore = MockTEL(canonicalTEL).balanceOf(user);
        uint256 destBalBefore = MockTEL(canonicalTEL).balanceOf(address(sepoliaITS));

        // note: direct calls to `ITS::transmitInterchainTransfer()` can only be called by the token
        // thus it is disabled on Ethereum since ethTEL doesn't have this function
        vm.prank(user);
        vm.expectRevert();
        sepoliaITS.transmitInterchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, user, destinationChain, destAddressBytes, amount, ""
        );

        assertEq(MockTEL(canonicalTEL).balanceOf(user), srcBalBefore);
        assertEq(MockTEL(canonicalTEL).balanceOf(address(canonicalTELTokenManager)), destBalBefore);
    }

    // function test_tnFork_approveMessages() public {

    // function test_tnFork_execute() public {

        // todo: payload seems constructed by its, maybe delete

        // bytesSrcAddr = AddressBytes.toBytes(srcAddr)
        // bytesDestAddr = AddressBytes.toBytes(RWTEL) //todo: should be user?
        // bytes memory nestedPayload = abi.encode(u256MessageType=TRANSFER, b32TokenId, bytesSrcAddr, bytesdestAddr,
        // u256amount, data);
        // bytes memory wrappedPayload = abi.encode(u256MessageType=FROM_HUB, originalSourceChain, nestedPayload);

        // GatewayCaller::approveContractCall()
        // its::execute(commandId, sourceChain, sourceAddress, wrappedPayload, wrappedPayloadHash)

        // vm.prank(user)
        // its.interchainTransfer();
    // }




    /// @dev Outbound ITS bridge tests

//     // function test_tnFork_itsInterchainTransfer_RWTEL() public {}
//     // function test_tnFork_itsTransmitInterchainTransfer_RWTEL() public {

    // function test_sepoliaFork_approveMessages() public {

    // function test_sepoliaFork_execute() public {



    //todo: fuzz tests for rwTEL, TEL bridging, rwteltest.t.sol
    //todo: fork tests for TEL bridging
    //todo: incorporate RWTEL contracts to TN protocol on rust side

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
