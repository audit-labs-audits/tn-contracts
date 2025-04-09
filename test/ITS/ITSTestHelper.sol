/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { IAxelarGateway } from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
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
import { Salts, ImplSalts } from "../../deployments/utils/Create3Utils.sol";
import { ITSUtils } from "../../deployments/utils/ITSUtils.sol";
import { ITS } from "../../deployments/Deployments.sol";
import { ITSGenesis } from "../../deployments/genesis/ITSGenesis.sol";

abstract contract ITSTestHelper is Test, ITSGenesis {
    function setUp_sepoliaFork_devnetConfig(
        address linker_,
        address sepoliaTel,
        address sepoliaIts,
        address sepoliaItf,
        address rwtelImpl
    )
        internal
    {
        linker = linker_;
        vm.deal(linker, 1 ether);
        tmOperator = AddressBytes.toBytes(linker);
        gasValue = 30_000_000;
        sepoliaTEL = IERC20(sepoliaTel);
        sepoliaITS = InterchainTokenService(sepoliaIts);
        sepoliaITF = InterchainTokenFactory(sepoliaItf);
        sepoliaGateway = IAxelarGateway(DEVNET_SEPOLIA_GATEWAY);
        // etch RWTEL impl bytecode for fetching origin linkedTokenId
        originTEL = address(sepoliaTEL);
        originChainName_ = DEVNET_SEPOLIA_CHAIN_NAME;
        governanceAddress_ = address(linker);
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        RWTEL temp = ITSUtils.instantiateRWTELImpl(sepoliaIts);
        vm.etch(rwtelImpl, address(temp).code);
        customLinkedTokenId = RWTEL(payable(rwtelImpl)).interchainTokenId();

        // note that TN must be added as a trusted chain to the Ethereum ITS contract
        vm.prank(sepoliaITS.owner());
        sepoliaITS.setTrustedAddress(TN_CHAIN_NAME, ITS_HUB_ROUTING_IDENTIFIER);
    }

    /// @notice Test utility for deploying ITS architecture, including RWTEL and its TokenManager, via create3
    /// @dev Used for tests only since live deployment is obviated by genesis precompiles
    function setUp_tnFork_devnetConfig_create3(address admin, address originTEL) internal {
        linker = admin;
        vm.deal(linker, 1 ether);

        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        (address precalculatedITS, address precalculatedWTEL, address precalculatedRWTEL) =
            _precalculateCreate3ConstructorArgs(create3, admin);

        _setUpDevnetConfig(admin, originTEL, precalculatedWTEL, precalculatedRWTEL);

        vm.startPrank(admin);

        // RWTEL impl's bytecode is used to fetch devnet tokenID for TNTokenHandler::constructor
        wTEL = ITSUtils.instantiateWTEL();
        rwTELImpl = ITSUtils.instantiateRWTELImpl(precalculatedITS);
        customLinkedTokenId = rwTELImpl.interchainTokenId();

        gatewayImpl = ITSUtils.instantiateAxelarAmplifierGatewayImpl();
        gateway = ITSUtils.instantiateAxelarAmplifierGateway(address(gatewayImpl));
        tokenManagerDeployer = ITSUtils.instantiateTokenManagerDeployer();
        interchainTokenImpl = ITSUtils.instantiateInterchainTokenImpl(create3.deployedAddress("", admin, salts.itsSalt));
        itDeployer = ITSUtils.instantiateInterchainTokenDeployer(address(interchainTokenImpl));
        tokenManagerImpl = ITSUtils.instantiateTokenManagerImpl(create3.deployedAddress("", admin, salts.itsSalt));
        tnTokenHandler = ITSUtils.instantiateTokenHandler(customLinkedTokenId);
        gasServiceImpl = ITSUtils.instantiateAxelarGasServiceImpl();
        gasService = ITSUtils.instantiateAxelarGasService(address(gasServiceImpl));
        gatewayCaller = ITSUtils.instantiateGatewayCaller(address(gateway), address(gasService));
        itsImpl = ITSUtils.instantiateITSImpl(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            create3.deployedAddress("", admin, salts.itfSalt),
            address(tokenManagerImpl),
            address(tnTokenHandler),
            address(gatewayCaller)
        );
        its = ITSUtils.instantiateITS(address(itsImpl));
        itFactoryImpl = ITSUtils.instantiateITFImpl(address(its));
        itFactory = ITSUtils.instantiateITF(address(itFactoryImpl));

        rwtelOwner = admin;
        rwTEL = ITSUtils.instantiateRWTEL(address(rwTELImpl));
        rwTEL.initialize(governanceAddress_, maxToClean, rwtelOwner);
        // mock-seed rwTEL with TEL total supply as genesis precompile
        vm.deal(address(rwTEL), telTotalSupply);

        rwTELTokenManager = ITSUtils.instantiateRWTELTokenManager(address(its), customLinkedTokenId);

        customLinkedTokenSalt = rwTEL.linkedTokenDeploySalt();
        originTELTokenManager = TokenManager(rwTEL.tokenManagerAddress());
        assertEq(customLinkedTokenId, rwTEL.interchainTokenId());

        vm.stopPrank();

        assertEq(address(its), create3.deployedAddress("", admin, salts.itsSalt));
        assertEq(address(itFactory), create3.deployedAddress("", admin, salts.itfSalt));
    }

    /// @notice Simulates genesis instantiation of ITS, RWTEL, and its TokenManager. Targets `deployments.json`
    /// @dev For devnet, a developer admin address serves all permissioned roles
    function setUp_tnFork_devnetConfig_genesis(
        ITS memory genesisITSTargets,
        address admin,
        address originTEL,
        address wtel,
        address rwtelImpl,
        address rwtel,
        address rwtelTokenManager
    )
        internal
    {
        linker = admin;
        vm.deal(linker, 1 ether);

        // first set target genesis addresses in state (not yet deployed) for use with recording
        _setGenesisTargets(genesisITSTargets, payable(wtel), payable(rwtelImpl), payable(rwtel), rwtelTokenManager);

        // instantiate deployer for state diff recording and set up config vars for devnet
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        _setUpDevnetConfig(admin, originTEL, wtel, rwtel);

        instantiateAxelarAmplifierGatewayImpl();
        instantiateAxelarAmplifierGateway(address(gatewayImpl));
        instantiateTokenManagerDeployer();
        instantiateInterchainTokenImpl(address(its));
        instantiateInterchainTokenDeployer(address(interchainTokenImpl));
        instantiateTokenManagerImpl(address(its));
        instantiateAxelarGasServiceImpl();
        instantiateAxelarGasService(address(gasServiceImpl));
        instantiateGatewayCaller(address(gateway), address(gasService));
        instantiateITSImpl(
            address(tokenManagerDeployer),
            address(itDeployer),
            address(gateway),
            address(gasService),
            address(itFactory),
            address(tokenManagerImpl),
            address(tnTokenHandler),
            address(gatewayCaller)
        );
        instantiateITS(address(itsImpl));
        instantiateITFImpl(address(its));
        instantiateITF(address(itFactoryImpl));

        instantiateWTEL();
        instantiateRWTELImpl(address(its));
        rwtelOwner = admin;
        instantiateRWTEL(address(rwTELImpl));
        // mock-seed rwTEL with TEL total supply as genesis precompile
        vm.deal(address(rwTEL), telTotalSupply);

        customLinkedTokenSalt = rwTEL.linkedTokenDeploySalt();
        originTELTokenManager = TokenManager(rwTEL.tokenManagerAddress());
        customLinkedTokenId = rwTEL.interchainTokenId();
        instantiateTokenHandler(customLinkedTokenId);
        instantiateRWTELTokenManager(address(its), customLinkedTokenId);
    }

    /// @dev Assert correctness of origin ITS return values against TN contracts
    function _devnetAsserts_rwTEL_rwTELTokenManager(
        bytes32 expectedTELTokenId,
        bytes32 returnedTELSalt,
        bytes32 returnedTELTokenId,
        address returnedTELTokenManager
    )
        internal
        view
    {
        // config asserts
        assertEq(expectedTELTokenId, customLinkedTokenId);
        assertEq(returnedTELSalt, customLinkedTokenSalt);
        assertEq(returnedTELTokenId, customLinkedTokenId);
        assertEq(returnedTELTokenManager, address(originTELTokenManager));

        // rwtel asserts, sanity first
        assertEq(customLinkedTokenSalt, rwTEL.linkedTokenDeploySalt());
        assertEq(customLinkedTokenId, rwTEL.interchainTokenId());
        assertEq(address(originTELTokenManager), rwTEL.tokenManagerAddress());
        assertEq(returnedTELSalt, rwTEL.linkedTokenDeploySalt());
        assertEq(returnedTELTokenId, rwTEL.tokenManagerCreate3Salt());
        assertEq(returnedTELTokenManager, rwTEL.tokenManagerAddress());

        // its asserts
        assertEq(address(rwTEL), its.interchainTokenAddress(returnedTELTokenId));
        assertEq(customLinkedTokenId, its.interchainTokenId(address(0x0), returnedTELSalt));
        // ITF::linkedTokenIds are chain-specific so TN itFactory should return differently
        assertFalse(customLinkedTokenId == itFactory.linkedTokenId(linker, salts.registerCustomTokenSalt));
    }

    /// @dev Overwrites TN devnet config with given `newSigner` as sole verifier for tests
    function _overwriteWeightedSigners(address newSigner) internal returns (WeightedSigners memory, bytes32) {
        WeightedSigners memory oldSigners = WeightedSigners(signerArray, threshold, nonce);

        ampdVerifierSigners[0] = newSigner;
        signerArray[0] = WeightedSigner(newSigner, weight);
        WeightedSigners memory newSigners = WeightedSigners(signerArray, threshold, nonce);

        // preobtained signature of gateway.messageHashToSign(signersHash, dataHash)
        bytes[] memory adminSig = new bytes[](1);
        adminSig[0] =
            hex"1a2949337b09a56bb7f741930c222c42666b25db1caa04aa3abb0abfaeaf415904c4a13f37fb6162966a23be2473475354bd32d149cd810bf7fea733c4bdb9331c";
        Proof memory newProof = Proof(oldSigners, adminSig);

        vm.warp(block.timestamp + minimumRotationDelay);
        gateway.rotateSigners(newSigners, newProof);

        bytes32 newSignersHash = keccak256(abi.encode(newSigners));
        return (newSigners, newSignersHash);
    }

    /// @dev Overwrites a origin chain gateway's verifiers with `newSigner` as sole verifier for tests
    /// @notice Required bc origin gateways use a legacy version incompatible with _overwriteWeightedSigners
    function _eth_overwriteWeightedSigners(
        address targetGateway,
        address newSigner
    )
        internal
        returns (bytes32, address[] memory, uint256[] memory)
    {
        address[] memory newOperators = new address[](1);
        newOperators[0] = newSigner;
        uint256[] memory weights = new uint256[](1);
        weights[0] = weight;
        bytes memory params = abi.encode(newOperators, weights, threshold);
        bytes32 newOperatorsHash = keccak256(params);

        // mock `transferOperatorship()` state changes
        (, bytes memory ret) = targetGateway.call(abi.encodeWithSignature("authModule()"));
        address authModule = abi.decode(ret, (address));
        bytes32 currentEpochSlot = bytes32(0x0);
        bytes32 epochForTests = 0x00000000000000000000000000000000000000000000000000000000000000ae; // rewind to a known
            // epoch
        vm.store(authModule, currentEpochSlot, epochForTests);
        bytes32 hashForEpochTestSlot = 0xcd308dfe822f4a376d452f3c35929b255b891b4318e82a1bcf379137aa8f8340;
        vm.store(authModule, hashForEpochTestSlot, newOperatorsHash);

        // derive epochForHash mapping storage slot
        bytes32 epochForHashBaseSlot = bytes32(abi.encode(2)); // `epochForHash` is in AuthModule storage slot 2
        bytes32 epochForHashTestSlot = keccak256(bytes.concat(newOperatorsHash, epochForHashBaseSlot));
        vm.store(authModule, epochForHashTestSlot, epochForTests);

        // assert correct slot was written to
        (, bytes memory r) = authModule.call(abi.encodeWithSignature("epochForHash(bytes32)", newOperatorsHash));
        assert(abi.decode(r, (bytes32)) == epochForTests);

        return (newOperatorsHash, newOperators, weights);
    }

    /// @dev Returns a origin chain gateway's `approveContractCall()` parameters for signing
    /// @notice Required bc origin gateways use a legacy version incompatible with `approveMessages()`
    function _getLegacyGatewayApprovalParams(
        bytes32 commandId,
        string memory sourceChain,
        string memory sourceAddressString,
        address destinationAddress,
        bytes memory wrappedPayload
    )
        internal
        pure
        returns (bytes memory, bytes32)
    {
        bytes32[] memory commandIds = new bytes32[](1);
        commandIds[0] = commandId;
        string[] memory commands = new string[](1);
        commands[0] = "approveContractCall";
        bytes[] memory approveParams = new bytes[](1);
        approveParams[0] =
            abi.encode(sourceChain, sourceAddressString, destinationAddress, keccak256(wrappedPayload), bytes32(0x0), 0);

        bytes memory executeData = abi.encode(SEPOLIA_CHAINID, commandIds, commands, approveParams);
        bytes32 executeHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(executeData)));

        return (executeData, executeHash);
    }

    /// @notice Redeclared event from `IAxelarGMPGateway` for asserts
    event ContractCall(
        address indexed sender,
        string destinationChain,
        string destinationContractAddress,
        bytes32 indexed payloadHash,
        bytes payload
    );

    /// @notice Redeclared event from `BaseAmplifierGateway` for asserts
    event MessageApproved(
        bytes32 indexed commandId,
        string sourceChain,
        string messageId,
        string sourceAddress,
        address indexed contractAddress,
        bytes32 indexed payloadHash
    );

    /// @notice Redeclared event from `BaseAmplifierGateway` for asserts
    event MessageExecuted(bytes32 indexed commandId);
}

contract HarnessCreate3FixedAddressForITS is Create3AddressFixed {
    function create3Address(bytes32 deploySalt) public view returns (address) {
        return _create3Address(deploySalt);
    }
}

/// @dev Read by ITS for metadata registration and used for tests
contract MockTEL is ERC20 {
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    function name() public view virtual override returns (string memory) {
        return "Mock Telcoin";
    }

    function symbol() public view virtual override returns (string memory) {
        return "mockTEL";
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
