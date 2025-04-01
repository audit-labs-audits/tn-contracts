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
import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../../src/WTEL.sol";
import { RWTEL } from "../../src/RWTEL.sol";
import { ExtCall } from "../../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../../deployments/utils/Create3Utils.sol";
import { ITSUtils } from "../../deployments/utils/ITSUtils.sol";
import { HarnessCreate3FixedAddressForITS, MockTEL } from "./ITSMocks.sol";

contract InterchainTokenServiceTest is Test, ITSUtils {
    // TN contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;

    // canonical "Ethereum" config (no forking done here but config stands)
    MockTEL mockTEL; // not used except to etch bytecode onto canonicalTEL
    address ethereumTEL = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL
    TokenManager canonicalTELTokenManager;

    // Axelar ITS core contracts
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

    address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23;
    address deployerEOA = admin; // only used for devnet
    address rwtelOwner = admin; // devnet only, no owner for mainnet

    function setUp() public {
        mockTEL = new MockTEL();
        canonicalTEL = ethereumTEL;
        vm.etch(canonicalTEL, address(mockTEL).code);

        wTEL = new WTEL();

        // note: devnet only: CREATE3 contract deployed via `create2`
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        // ITS address must be derived w/ sender + salt pre-deploy, for TokenManager && InterchainToken constructors
        address expectedITS = create3.deployedAddress("", deployerEOA, salts.itsSalt);
        // must precalculate ITF proxy to avoid `ITS::constructor()` revert
        address expectedITF = create3.deployedAddress("", deployerEOA, salts.itfSalt);
        _setUpDevnetConfig(admin, canonicalTEL, address(wTEL), expectedITS, expectedITF);

        // note: devnet only
        rwtelOwner = admin;
        // note: overwrite chainName_ in setup params to test ITS somewhat chain agnostically
        chainName_ = DEVNET_SEPOLIA_CHAIN_NAME;
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // note: ITS deterministic create3 deployments depend on `sender` for devnet only
        vm.startPrank(deployerEOA);

        // deploy ITS core suite; use config from storage
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

        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);

        vm.stopPrank(); // `deployerEOA`

        // asserts
        assertEq(precalculatedITS, address(its));
        assertEq(precalculatedITFactory, address(itFactory));
    }

    function test_setUp() public view {
        // wTEL sanity tests
        assertTrue(address(wTEL).code.length > 0);
        string memory wName = wTEL.name();
        assertEq(wName, "Wrapped Telcoin");
        string memory wSymbol = wTEL.symbol();
        assertEq(wSymbol, "wTEL");

        // gateway sanity tests
        assertEq(gateway.owner(), gatewayOwner);
        assertEq(gateway.implementation(), address(gatewayImpl));
        assertEq(gateway.contractId(), salts.gatewaySalt);
        assertEq(gateway.operator(), gatewayOperator);
        assertEq(gateway.previousSignersRetention(), previousSignersRetention);
        assertEq(gateway.domainSeparator(), domainSeparator);
        assertEq(gateway.minimumRotationDelay(), minimumRotationDelay);
        assertEq(gateway.epoch(), 1);
        assertEq(gateway.signersHashByEpoch(1), keccak256(abiEncodedWeightedSigners));
        assertEq(gateway.epochBySignersHash(keccak256(abiEncodedWeightedSigners)), 1);
        assertEq(gateway.lastRotationTimestamp(), block.number);
        assertEq(gateway.timeSinceRotation(), 0);

        // ITS periphery sanity tests
        assertEq(interchainTokenImpl.interchainTokenService(), address(its));
        assertEq(itDeployer.implementationAddress(), address(interchainTokenImpl));
        assertEq(tokenManagerImpl.interchainTokenService(), address(its));
        assertEq(gasService.implementation(), address(gasServiceImpl));
        assertEq(gasService.gasCollector(), gasCollector);
        assertEq(gasService.contractId(), salts.gsSalt);
        assertEq(address(gatewayCaller.gateway()), address(gateway));
        assertEq(address(gatewayCaller.gasService()), address(gasService));
        // ITS sanity tests for immutables can be checked on impl since they're set in bytecode
        assertEq(itsImpl.tokenManagerDeployer(), address(tokenManagerDeployer));
        assertEq(itsImpl.interchainTokenDeployer(), address(itDeployer));
        assertEq(address(itsImpl.gateway()), address(gateway));
        assertEq(address(itsImpl.gasService()), address(gasService));
        assertEq(itsImpl.interchainTokenFactory(), address(itFactory));
        assertEq(itsImpl.chainNameHash(), keccak256(bytes(chainName_)));
        assertEq(itsImpl.tokenManager(), address(tokenManagerImpl));
        assertEq(itsImpl.tokenHandler(), address(tokenHandler));
        assertEq(itsImpl.gatewayCaller(), address(gatewayCaller));
        assertEq(itsImpl.tokenManagerImplementation(0), address(tokenManagerImpl));
        // ITS proxy sanity tests
        assertEq(its.tokenManagerImplementation(0), address(tokenManagerImpl));
        assertEq(
            its.getExpressExecutor(
                bytes32(0x0), chainName_, Strings.toString(uint256(uint160(address(rwTEL)))), bytes32(0x0)
            ),
            address(0x0)
        );

        // rwTEL sanity tests
        assertEq(rwTEL.stakeManager(), 0x07E17e17E17e17E17e17E17E17E17e17e17E17e1);
        assertEq(address(rwTEL.interchainTokenService()), address(its));
        assertEq(rwTEL.owner(), rwtelOwner);
        assertTrue(address(rwTEL).code.length > 0);
        assertEq(rwTEL.name(), name_);
        assertEq(rwTEL.symbol(), symbol_);
        assertEq(rwTEL.recoverableWindow(), recoverableWindow_);
        assertEq(rwTEL.governanceAddress(), governanceAddress_);
        assertEq(rwTEL.baseToken(), address(wTEL));
        assertEq(rwTEL.decimals(), wTEL.decimals());
        // note that rwTEL ITS salt and tokenId are based on canonicalTEL
        bytes32 rwtelDeploySalt = rwTEL.canonicalInterchainTokenDeploySalt();
        assertEq(rwtelDeploySalt, itFactory.canonicalInterchainTokenDeploySalt(address(canonicalTEL)));
        bytes32 rwtelTokenId = rwTEL.interchainTokenId();
        assertEq(rwtelTokenId, rwTEL.tokenManagerCreate3Salt());
        assertEq(rwtelTokenId, itFactory.canonicalInterchainTokenId(address(canonicalTEL)));
        assertEq(rwtelTokenId, its.interchainTokenId(address(0x0), rwtelDeploySalt));
    }

    /// @dev Test the flow for registering a token with ITS hub + deploying its manager
    /// @notice In prod, these calls must be performed on Ethereum prior to TN genesis
    function test_eth_registerCanonicalInterchainToken() public {
        // Register canonical TEL metadata with Axelar chain's ITS hub, this step requires gas prepayment
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (canonicalInterchainSalt, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

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
        bytes memory restoreCodeITS = address(its).code;
        vm.etch(address(its), type(HarnessCreate3FixedAddressForITS).runtimeCode);
        HarnessCreate3FixedAddressForITS itsCreate3 = HarnessCreate3FixedAddressForITS(address(its));
        // note to deploy TokenManagers ITS uses a different create3 salt schema that 'wraps' the token's canonical
        // deploy salt
        bytes32 tmDeploySaltIsTELInterchainTokenId =
            keccak256(abi.encode(keccak256("its-interchain-token-id"), address(0x0), canonicalInterchainSalt));
        assertEq(itsCreate3.create3Address(tmDeploySaltIsTELInterchainTokenId), address(canonicalTELTokenManager));
        vm.etch(address(its), restoreCodeITS);

        // ITS asserts post registration && deployed canonicalTELTokenManager
        address canonicalTELTokenManagerExpected = its.tokenManagerAddress(canonicalInterchainTokenId);
        assertEq(address(canonicalTELTokenManager), canonicalTELTokenManagerExpected);
        assertTrue(canonicalTELTokenManagerExpected.code.length > 0);
        assertEq(address(its.deployedTokenManager(canonicalInterchainTokenId)), address(canonicalTELTokenManager));
        assertEq(its.registeredTokenAddress(canonicalInterchainTokenId), canonicalTEL);

        // canonicalTEL TokenManager asserts
        assertEq(canonicalTELTokenManager.contractId(), keccak256("token-manager"));
        assertEq(canonicalTELTokenManager.interchainTokenId(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(canonicalTELTokenManager.implementationType(), uint256(ITokenManagerType.TokenManagerType.LOCK_UNLOCK));
        assertEq(canonicalTELTokenManager.tokenAddress(), address(canonicalTEL));
        assertEq(canonicalTELTokenManager.isOperator(address(0x0)), true);
        assertEq(canonicalTELTokenManager.isOperator(address(its)), true);
        assertEq(canonicalTELTokenManager.isFlowLimiter(address(its)), true);
        assertEq(canonicalTELTokenManager.flowLimit(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowInAmount(), 0); // set by ITS
        assertEq(canonicalTELTokenManager.flowOutAmount(), 0); // set by ITS
        bytes memory ethTMSetupParams = abi.encode(bytes(""), canonicalTEL);
        assertEq(canonicalTELTokenManager.getTokenAddressFromParams(ethTMSetupParams), canonicalTEL);

        // rwtel asserts
        bytes32 rwtelTokenId = rwTEL.interchainTokenId();
        assertEq(rwtelTokenId, its.interchainTokenId(address(0x0), canonicalInterchainSalt));
        assertEq(rwtelTokenId, canonicalInterchainTokenId);
        assertEq(rwtelTokenId, tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.tokenManagerCreate3Salt(), tmDeploySaltIsTELInterchainTokenId);
        assertEq(rwTEL.canonicalInterchainTokenDeploySalt(), canonicalInterchainSalt);
    }

    /// @notice `deployRemoteCanonicalInterchainToken` will route a `MESSAGE_TYPE_LINK_TOKEN` through ITS hub
    /// that is guaranteed to revert deployment to genesis contracts; skip this step for testnet & mainnet
    function test_eth_deployRemoteCanonicalInterchainToken() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
        // note this remote canonical interchain token step is for devnet only, obviated by testnet & mainnet genesis
        bytes32 remoteCanonicalTokenId =
            itFactory.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL, destinationChain, gasValue);

        /// @dev for devnet, relayer will forward link msg to TN thru ITS hub & use it to deploy rwtel tokenmanager

        assertEq(remoteCanonicalTokenId, canonicalInterchainTokenId);
    }

    function test_eth_interchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        uint256 amount = 42;
        MockTEL(canonicalTEL).mint(address(this), amount);
        MockTEL(canonicalTEL).approve(address(its), amount);

        bytes memory destinationAddress = AddressBytes.toBytes(address(0xbeef));
        its.interchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, destinationChain, destinationAddress, amount, "", gasValue
        );
    }

    function test_eth_transmitInterchainTransfer_TEL() public {
        // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
        uint256 gasValue = 100; // dummy gas value specified for multicalls
        (, canonicalInterchainTokenId, canonicalTELTokenManager) =
            eth_registerCanonicalTELAndDeployTELTokenManager(canonicalTEL, its, itFactory, gasValue);

        // note that TN must have been added as a trusted chain to the Ethereum ITS contract
        string memory destinationChain = TN_CHAIN_NAME;
        vm.prank(itsOwner);
        its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        address user = address(0x42);
        uint256 amount = 42;
        MockTEL(canonicalTEL).mint(user, amount);
        vm.prank(user);
        MockTEL(canonicalTEL).approve(address(its), amount);

        bytes memory destinationAddress = AddressBytes.toBytes(address(0xbeef));

        // note: direct calls to `ITS::transmitInterchainTransfer()` can only be called by the token
        // thus it is disabled on Ethereum since ethTEL doesn't have this function
        vm.expectRevert();
        its.transmitInterchainTransfer{ value: gasValue }(
            canonicalInterchainTokenId, user, destinationChain, destinationAddress, amount, ""
        );
    }
}
