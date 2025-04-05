/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Test, console2 } from "forge-std/Test.sol";

/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

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
        sepoliaTEL = IERC20(sepoliaTel);
        sepoliaITS = InterchainTokenService(sepoliaIts);
        sepoliaITF = InterchainTokenFactory(sepoliaItf);
        sepoliaGateway = IAxelarGateway(DEVNET_SEPOLIA_GATEWAY);
        canonicalTEL = address(sepoliaTEL);
    }

    /// @notice Test utility for deploying ITS architecture, including RWTEL and its TokenManager, via create3
    /// @dev Used for tests only since live deployment is obviated by genesis precompiles
    function _setUp_tnFork_devnetConfig_create3(address admin, address canonicalTEL) internal {
        _setUpDevnetConfig(admin, canonicalTEL);

        vm.startPrank(admin);

        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        wTEL = ITSUtils.instantiateWTEL();

        // start with RWTEL to fetch devnet tokenID for TNTokenHandler::constructor
        address precalculatedITS = create3.deployedAddress("", admin, salts.itsSalt);
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
        address rwtelImpl,
        address rwtel,
        address rwtelTokenManager
    )
        internal
    {
        // first set target genesis addresses in state (not yet deployed) for use with recording
        _setGenesisTargets(genesisITSTargets, rwtelImpl, rwtel, rwtelTokenManager);

        // instantiate deployer for state diff recording and set up config vars for devnet
        create3 = new Create3Deployer{ salt: salts.Create3DeployerSalt }();
        _setUpDevnetConfig(admin, canonicalTEL);

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
