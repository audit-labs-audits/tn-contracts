/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
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
    function setUp_sepoliaFork_devnetConfig(address sepoliaTel, address sepoliaIts, address sepoliaItf) internal {
        gasValue = 30_000_000;
        sepoliaTEL = IERC20(sepoliaTel);
        sepoliaITS = InterchainTokenService(sepoliaIts);
        sepoliaITF = InterchainTokenFactory(sepoliaItf);
        sepoliaGateway = IAxelarGateway(DEVNET_SEPOLIA_GATEWAY);
        canonicalTEL = address(sepoliaTEL);
    }

    /// @notice Test utility for deploying ITS architecture, including RWTEL and its TokenManager, via create3
    /// @dev Used for tests only since live deployment is obviated by genesis precompiles
    function setUp_tnFork_devnetConfig_create3(address admin, address canonicalTEL) internal {
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        (address precalculatedITS, address precalculatedWTEL, address precalculatedRWTEL) = _precalculateCreate3ConstructorArgs(create3, admin);

        _setUpDevnetConfig(admin, canonicalTEL, precalculatedWTEL, precalculatedRWTEL);

        vm.startPrank(admin);

        // RWTEL impl's bytecode is used to fetch devnet tokenID for TNTokenHandler::constructor
        wTEL = ITSUtils.instantiateWTEL();
        rwTELImpl = ITSUtils.instantiateRWTELImpl(precalculatedITS);
        canonicalInterchainTokenId = rwTELImpl.interchainTokenId();

        gatewayImpl = ITSUtils.instantiateAxelarAmplifierGatewayImpl();
        gateway = ITSUtils.instantiateAxelarAmplifierGateway(address(gatewayImpl));
        tokenManagerDeployer = ITSUtils.instantiateTokenManagerDeployer();
        interchainTokenImpl = ITSUtils.instantiateInterchainTokenImpl(create3.deployedAddress("", admin, salts.itsSalt));
        itDeployer = ITSUtils.instantiateInterchainTokenDeployer(address(interchainTokenImpl));
        tokenManagerImpl = ITSUtils.instantiateTokenManagerImpl(create3.deployedAddress("", admin, salts.itsSalt));
        tnTokenHandler = ITSUtils.instantiateTokenHandler(canonicalInterchainTokenId);
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

        rwTELTokenManager = ITSUtils.instantiateRWTELTokenManager(address(its), canonicalInterchainTokenId);

        canonicalInterchainTokenSalt = rwTEL.canonicalInterchainTokenDeploySalt();
        canonicalTELTokenManager = TokenManager(rwTEL.tokenManagerAddress());
        assertEq(canonicalInterchainTokenId, rwTEL.interchainTokenId());

        vm.stopPrank();

        assertEq(address(its), create3.deployedAddress("", admin, salts.itsSalt));
        assertEq(address(itFactory), create3.deployedAddress("", admin, salts.itfSalt));
    }

    /// @notice Simulates genesis instantiation of ITS, RWTEL, and its TokenManager. Targets `deployments.json`
    /// @dev For devnet, a developer admin address serves all permissioned roles
    function setUp_tnFork_devnetConfig_genesis(
        ITS memory genesisITSTargets,
        address admin,
        address canonicalTEL,
        address wtel,
        address rwtelImpl,
        address rwtel,
        address rwtelTokenManager
    )
        internal
    {
        // first set target genesis addresses in state (not yet deployed) for use with recording
        _setGenesisTargets(genesisITSTargets, payable(wtel), payable(rwtelImpl), payable(rwtel), rwtelTokenManager);

        // instantiate deployer for state diff recording and set up config vars for devnet
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        _setUpDevnetConfig(admin, canonicalTEL, wtel, rwtel);

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

        canonicalInterchainTokenSalt = rwTEL.canonicalInterchainTokenDeploySalt();
        canonicalTELTokenManager = TokenManager(rwTEL.tokenManagerAddress());
        canonicalInterchainTokenId = rwTEL.interchainTokenId();
        instantiateTokenHandler(canonicalInterchainTokenId);
        instantiateRWTELTokenManager(address(its), canonicalInterchainTokenId);
    }

    /// @dev Assert correctness of canonical ITS return values against TN contracts
    function _devnetAsserts_rwTEL_rwTELTokenManager(bytes32 expectedTELTokenId, bytes32 returnedTELSalt, bytes32 returnedTELTokenId, address returnedTELTokenManager) internal view {
        // config asserts
        assertEq(expectedTELTokenId, canonicalInterchainTokenId);
        assertEq(returnedTELSalt, canonicalInterchainTokenSalt);
        assertEq(returnedTELTokenId, canonicalInterchainTokenId);
        assertEq(returnedTELTokenManager, address(canonicalTELTokenManager));

        // rwtel asserts, sanity first
        assertEq(canonicalInterchainTokenSalt, rwTEL.canonicalInterchainTokenDeploySalt());
        assertEq(canonicalInterchainTokenId, rwTEL.interchainTokenId());
        assertEq(address(canonicalTELTokenManager), rwTEL.tokenManagerAddress());
        assertEq(returnedTELSalt, rwTEL.canonicalInterchainTokenDeploySalt());
        assertEq(returnedTELTokenId, rwTEL.tokenManagerCreate3Salt());
        assertEq(returnedTELTokenManager, rwTEL.tokenManagerAddress());

        // its asserts
        assertEq(address(rwTEL), its.interchainTokenAddress(returnedTELTokenId));
        assertEq(canonicalInterchainTokenId, its.interchainTokenId(address(0x0), returnedTELSalt));
        // ITF::canonicalInterchainTokenIds are chain-specific so TN itFactory should return differently
        assertFalse(canonicalInterchainTokenId == itFactory.canonicalInterchainTokenId(canonicalTEL));
    }

    /// @dev Overwrites devnet config with given `newSigner` for tests
    function _overwriteWeightedSigners(address newSigner) internal returns (WeightedSigners memory) {
        WeightedSigners memory oldSigners = WeightedSigners(signerArray, threshold, nonce);

        ampdVerifierSigners[0] = newSigner;
        signerArray[0] = WeightedSigner(newSigner, weight);
        WeightedSigners memory newSigners = WeightedSigners(signerArray, threshold, nonce);
 
        // preobtained signature of `_getEIP191Hash(destinationGateway, keccak256(abi.encode(CommandType.RotateSigners, newSigners)))`
        bytes[] memory adminSig = new bytes[](1);
        adminSig[0] = hex"64ca5bcdf1f8bb9429538f116fd3766ff24b23c9053697cbce1065e62daf444f2c48c57596bb79eb6f39a2089a9456fafc59e70c1be707aaf615c162f9f1d76b1c";
        Proof memory newProof = Proof(oldSigners, adminSig);

        vm.warp(block.timestamp + minimumRotationDelay);
        gateway.rotateSigners(newSigners, newProof);

        return newSigners;
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
