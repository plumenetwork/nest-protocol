// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

// utils
import {Test} from "forge-std/Test.sol";
import {Options, DefenderOptions, TxOverrides} from "@openzeppelin/foundry-upgrades/src/Options.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

// contracts
import {NestVault} from "contracts/NestVault.sol";
import {MockNestVault} from "test/mock/MockNestVault.sol";
import {Constants} from "script/Constants.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {NestVaultPredicateProxy} from "contracts/NestVaultPredicateProxy.sol";
import {MockServiceManager} from "test/mock/MockServiceManager.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Authority} from "@solmate/auth/Auth.sol";

// interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Helper is Constants, Test {
    MockNestVault internal immutable NEST_VAULT;

    NestVaultPredicateProxy internal immutable NEST_VAULT_PREDICATE_PROXY;

    MockServiceManager internal immutable MOCK_SERVICE_MANAGER;

    RolesAuthority internal boringAuthority;

    NestVault _logic;

    /// @dev Constant address of Ethereum USDC whale for testing
    address public constant ETHEREUM_USDC_WHALE = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    constructor() {
        // deploy NestVault
        Options memory _nestVaultProxyOpts = Options({
            referenceContract: "",
            referenceBuildInfoDir: "",
            constructorData: abi.encode(NALPHA, USDC),
            exclude: new string[](0),
            unsafeAllow: "",
            unsafeAllowRenames: false,
            unsafeSkipProxyAdminCheck: false,
            unsafeSkipStorageCheck: false,
            unsafeSkipAllChecks: true,
            defender: DefenderOptions({
                useDefenderDeploy: false,
                skipVerifySourceCode: false,
                relayerId: "",
                salt: bytes32(0),
                upgradeApprovalProcessId: "",
                licenseType: "",
                skipLicenseType: false,
                txOverrides: TxOverrides({gasLimit: 30000000, gasPrice: 0, maxFeePerGas: 10, maxPriorityFeePerGas: 1}),
                metadata: ""
            })
        });
        address _accountantWithRateProviders = NALPHA_ACCOUNTANT;
        address _asset = USDC;
        address _owner = address(this);
        uint256 _minRate = 1e3;
        address _nestVaultProxy = Upgrades.deployTransparentProxy(
            "MockNestVault.sol",
            address(this),
            abi.encodeCall(NEST_VAULT.initialize, (_accountantWithRateProviders, _asset, _owner, _minRate)),
            _nestVaultProxyOpts
        );

        NEST_VAULT = MockNestVault(_nestVaultProxy);

        assertEq(NEST_VAULT.share(), NALPHA);
        assertEq(NEST_VAULT.decimals(), BoringVault(NALPHA).decimals());
        assertEq(NEST_VAULT.name(), BoringVault(NALPHA).name());
        assertEq(NEST_VAULT.symbol(), BoringVault(NALPHA).symbol());
        assertEq(NEST_VAULT.totalSupply(), BoringVault(NALPHA).totalSupply());
        assertEq(address(NEST_VAULT.accountantWithRateProviders()), NALPHA_ACCOUNTANT);
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = NEST_VAULT.eip712Domain();
        assertEq(fields, hex"0f");
        assertEq(name, BoringVault(NALPHA).name());
        assertEq(version, NEST_VAULT.version());
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(NEST_VAULT));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
        assertEq(NEST_VAULT.getRequestId(), 0);
        assertEq(NEST_VAULT.minRate(), 1e3);

        // deploy NestVaultPredicateProxy
        Options memory _nestVaultPredicateProxyOpts = Options({
            referenceContract: "",
            referenceBuildInfoDir: "",
            constructorData: "",
            exclude: new string[](0),
            unsafeAllow: "",
            unsafeAllowRenames: false,
            unsafeSkipProxyAdminCheck: false,
            unsafeSkipStorageCheck: false,
            unsafeSkipAllChecks: true,
            defender: DefenderOptions({
                useDefenderDeploy: false,
                skipVerifySourceCode: false,
                relayerId: "",
                salt: bytes32(0),
                upgradeApprovalProcessId: "",
                licenseType: "",
                skipLicenseType: false,
                txOverrides: TxOverrides({gasLimit: 30000000, gasPrice: 0, maxFeePerGas: 10, maxPriorityFeePerGas: 1}),
                metadata: ""
            })
        });
        MOCK_SERVICE_MANAGER = new MockServiceManager();
        address _nestVaultPredicateProxy = Upgrades.deployTransparentProxy(
            "NestVaultPredicateProxy.sol",
            address(this),
            abi.encodeCall(
                NEST_VAULT_PREDICATE_PROXY.initialize, (address(this), address(MOCK_SERVICE_MANAGER), POLICY_ID)
            ),
            _nestVaultPredicateProxyOpts
        );

        NEST_VAULT_PREDICATE_PROXY = NestVaultPredicateProxy(_nestVaultPredicateProxy);

        assertEq(NEST_VAULT_PREDICATE_PROXY.owner(), address(this));
        assertEq(NEST_VAULT_PREDICATE_PROXY.getPredicateManager(), address(MOCK_SERVICE_MANAGER));
        assertEq(NEST_VAULT_PREDICATE_PROXY.getPolicy(), POLICY_ID);
    }

    /// @dev Setup function that initializes the testing environment and sets public capabilities
    function setUp() public virtual {
        _logic = new NestVault(NALPHA);
        // set the authority
        boringAuthority = RolesAuthority(address(BoringVault(NALPHA).authority()));
        NEST_VAULT.setAuthority(Authority(address(boringAuthority)));
        NEST_VAULT_PREDICATE_PROXY.setAuthority(Authority(address(boringAuthority)));
        vm.startPrank(boringAuthority.owner());
        boringAuthority.setPublicCapability(NALPHA, BoringVault.enter.selector, true);
        boringAuthority.setPublicCapability(NALPHA, BoringVault.exit.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.deposit.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.mint.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.instantRedeem.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.requestRedeem.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.updateRedeem.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.fulfillRedeem.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.withdraw.selector, true);
        boringAuthority.setPublicCapability(address(NEST_VAULT), NEST_VAULT.redeem.selector, true);
        boringAuthority.setRoleCapability(
            OWNER_ROLE, address(NEST_VAULT_PREDICATE_PROXY), NEST_VAULT_PREDICATE_PROXY.pause.selector, true
        );
        boringAuthority.setUserRole(address(this), OWNER_ROLE, true);
        boringAuthority.setRoleCapability(
            OWNER_ROLE, address(NEST_VAULT_PREDICATE_PROXY), NEST_VAULT_PREDICATE_PROXY.setPolicy.selector, true
        );
        boringAuthority.setUserRole(address(this), OWNER_ROLE, true);
        boringAuthority.setRoleCapability(
            OWNER_ROLE,
            address(NEST_VAULT_PREDICATE_PROXY),
            NEST_VAULT_PREDICATE_PROXY.setPredicateManager.selector,
            true
        );
        boringAuthority.setUserRole(address(this), OWNER_ROLE, true);
        boringAuthority.setPublicCapability(
            address(NEST_VAULT_PREDICATE_PROXY),
            bytes4(keccak256("deposit(address,uint256,address,address,(string,uint256,address[],bytes[]))")),
            true
        );
        boringAuthority.setPublicCapability(
            address(NEST_VAULT_PREDICATE_PROXY),
            bytes4(keccak256("mint(address,uint256,address,address,(string,uint256,address[],bytes[]))")),
            true
        );
        vm.stopPrank();
    }

    function createValidSignature(
        MockNestVault _plumeVault,
        bytes32 nonce,
        uint256 validDeadline,
        address operator,
        address controller,
        uint256 controllerKey,
        bool approved
    ) public view returns (bytes memory) {
        bytes32 domainSeparator = _plumeVault.getDomainSeparatorV4();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                controller,
                operator,
                approved,
                nonce,
                validDeadline
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(controllerKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
