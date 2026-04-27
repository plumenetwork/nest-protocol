// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Authority} from "@solmate/auth/Auth.sol";

import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Constants} from "script/Constants.sol";
import {BlacklistHook} from "contracts/hooks/BlacklistHook.sol";
import {INestVaultCore} from "contracts/interfaces/INestVaultCore.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestShareSeizer} from "contracts/NestShareSeizer.sol";
import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {MockNestVault, NestVault} from "test/mock/MockNestVault.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";

contract NestShareSeizerTest is TestHelperOz5, Constants {
    uint32 internal constant EID = 1;

    MockNestShareOFT internal share;
    MockNestVault internal vault;
    MockRateProvider internal accountant;
    ERC20Mock internal asset;
    BlacklistHook internal hook;
    RolesAuthority internal authority;
    NestShareSeizer internal seizer;

    address internal userA = address(0x1);
    address internal userB = address(0x2);
    address internal proxyAdmin = makeAddr("proxyAdmin");

    uint256 internal constant SHARE_AMOUNT = 1_000_000;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        asset = new ERC20Mock("Asset", "AST");
        accountant = new MockRateProvider();
        accountant.setRate(2e6);

        share = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[EID])),
                abi.encodeWithSelector(NestShareOFT.initialize.selector, "Share", "SHARE", address(this), address(this))
            )
        );

        vault = MockNestVault(
            _deployContractAndProxy(
                type(MockNestVault).creationCode,
                abi.encode(payable(address(share))),
                abi.encodeWithSelector(
                    NestVault.initialize.selector, accountant, address(asset), address(this), 1, address(0)
                )
            )
        );

        authority = new RolesAuthority(address(this), Authority(address(0)));
        share.setAuthority(Authority(address(authority)));

        hook = new BlacklistHook(address(this), Authority(address(0)));
        hook.setAuthority(Authority(address(authority)));

        share.setBeforeTransferHook(address(hook));

        seizer = new NestShareSeizer(address(this), Authority(address(0)));

        authority.setRoleCapability(OWNER_ROLE, address(share), NestShareOFT.enter.selector, true);
        authority.setRoleCapability(OWNER_ROLE, address(share), NestShareOFT.exit.selector, true);
        authority.setRoleCapability(OWNER_ROLE, address(hook), BlacklistHook.setBlacklisted.selector, true);
        authority.setUserRole(address(seizer), OWNER_ROLE, true);
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }

    function _mintShares(address to, uint256 amount) internal {
        share.enter(address(0), ERC20(address(0)), 0, to, amount);
    }

    function test_canSeize_true_with_roles() public view {
        assertTrue(seizer.canSeize(share));
    }

    function test_canSeize_false_without_hook() public {
        share.setBeforeTransferHook(address(0));
        assertFalse(seizer.canSeize(share));
    }

    function test_canSeize_false_without_roles() public {
        authority.setUserRole(address(seizer), OWNER_ROLE, false);
        assertFalse(seizer.canSeize(share));
    }

    function test_seize_transfers_shares_and_blacklists() public {
        _mintShares(userA, SHARE_AMOUNT);

        seizer.seize(share, userA, userB, SHARE_AMOUNT);

        assertEq(share.balanceOf(userA), 0);
        assertEq(share.balanceOf(userB), SHARE_AMOUNT);
        assertTrue(hook.isBlacklisted(userA));
    }

    function test_seize_allows_blacklisted_sender() public {
        _mintShares(userA, SHARE_AMOUNT);
        hook.setBlacklisted(userA, true);

        seizer.seize(share, userA, userB, SHARE_AMOUNT);

        assertEq(share.balanceOf(userA), 0);
        assertEq(share.balanceOf(userB), SHARE_AMOUNT);
        assertTrue(hook.isBlacklisted(userA));
    }

    function test_seizeAndRedeem_transfers_assets_and_blacklists() public {
        _mintShares(userA, SHARE_AMOUNT);

        uint256 assetAmount = vault.convertToAssets(SHARE_AMOUNT);

        asset.mint(address(share), assetAmount);

        seizer.seizeAndRedeem(INestVaultCore(address(vault)), userA, userB, SHARE_AMOUNT);

        assertEq(asset.balanceOf(userB), assetAmount);
        assertEq(share.balanceOf(userA), 0);
        assertTrue(hook.isBlacklisted(userA));
    }
}
