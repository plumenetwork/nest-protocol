// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20Mock} from "@layerzerolabs/oft-evm-upgradeable/test/mocks/ERC20Mock.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MockNestVault} from "test/mock/MockNestVault.sol";
import {MockNestShareOFT} from "test/mock/MockNestShareOFT.sol";
import {MockRateProvider} from "test/mock/MockRateProvider.sol";
import {MockAuthority} from "test/mock/MockAuthority.sol";
import {NestVault} from "contracts/NestVault.sol";
import {NestShareOFT} from "contracts/NestShareOFT.sol";
import {NestVaultCoreTypes} from "contracts/libraries/nest-vault/NestVaultCoreTypes.sol";
import {Errors} from "contracts/types/Errors.sol";

contract NestVaultFeesTest is TestHelperOz5 {
    using FixedPointMathLib for uint256;

    uint32 internal constant LOCAL_EID = 1;

    MockNestVault internal vault;
    MockNestShareOFT internal share;
    ERC20Mock internal asset;
    MockRateProvider internal accountant;
    address internal proxyAdmin;

    address internal user = makeAddr("user");
    address internal feeReceiver = makeAddr("feeReceiver");

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        proxyAdmin = makeAddr("proxyAdmin");

        accountant = new MockRateProvider();
        accountant.setRate(1e6); // 1:1 rate

        asset = new ERC20Mock("Asset", "AST");

        share = MockNestShareOFT(
            _deployContractAndProxy(
                type(MockNestShareOFT).creationCode,
                abi.encode(address(endpoints[LOCAL_EID])),
                abi.encodeCall(NestShareOFT.initialize, ("Share", "SHARE", address(this), address(this)))
            )
        );

        vault = MockNestVault(
            _deployContractAndProxy(
                type(MockNestVault).creationCode,
                abi.encode(payable(address(share))),
                abi.encodeCall(
                    NestVault.initialize, (address(accountant), address(asset), address(this), 1, address(0))
                )
            )
        );

        MockAuthority mockAuth = new MockAuthority(true);
        share.setAuthority(Authority(address(mockAuth)));
        vault.setAuthority(Authority(address(mockAuth)));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositWithFee_reducesSharesMinted() public {
        uint32 depositFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(depositAmount, user);

        uint256 expectedFee = depositAmount * depositFee / 1_000_000;
        uint256 expectedShares = depositAmount - expectedFee;
        assertEq(sharesMinted, expectedShares, "Shares minted should reflect deposit fee");
        assertEq(share.balanceOf(user), expectedShares, "User share balance should match");
        assertEq(
            vault.claimableFees(NestVaultCoreTypes.Fees.Deposit),
            expectedFee,
            "Claimable deposit fees should be accrued"
        );
    }

    function test_mintWithFee_chargesMoreAssets() public {
        uint32 depositFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 sharesToMint = 990e6;
        uint256 requiredAssets = vault.previewMint(sharesToMint);

        _mintAndApprove(user, requiredAssets);

        vm.prank(user);
        uint256 assetsUsed = vault.mint(sharesToMint, user);

        assertEq(assetsUsed, requiredAssets, "Assets used should match preview");
        assertEq(share.balanceOf(user), sharesToMint, "User should receive exact shares requested");
        assertGt(
            vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), 0, "Deposit fee should be accrued from mint path"
        );
    }

    function test_previewDeposit_withFee_returnsReducedShares() public {
        uint32 depositFee = 20_000; // 2%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 depositAmount = 1_000e6;
        uint256 previewShares = vault.previewDeposit(depositAmount);

        uint256 expectedFee = depositAmount * depositFee / 1_000_000;
        uint256 expectedShares = depositAmount - expectedFee;
        assertEq(previewShares, expectedShares, "Preview should return fee-adjusted shares");
    }

    function test_previewMint_withFee_returnsInflatedAssets() public {
        uint32 depositFee = 50_000; // 5%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 sharesToMint = 950e6;
        uint256 previewAssets = vault.previewMint(sharesToMint);

        uint256 postFeeAssets = previewAssets - (previewAssets * depositFee / 1_000_000);
        uint256 previousPostFeeAssets = (previewAssets - 1) - ((previewAssets - 1) * depositFee / 1_000_000);

        assertEq(postFeeAssets, sharesToMint, "Preview should cover the requested post-fee assets");
        assertLt(previousPostFeeAssets, sharesToMint, "Preview should return the minimal gross assets");
    }

    function test_previewMint_withFee_usesMinimalGrossAssetsForDustAmounts() public {
        uint32 depositFee = 200_000; // 20%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 sharesToMint = 1;
        uint256 previewAssets = vault.previewMint(sharesToMint);

        assertEq(previewAssets, 1, "Preview should not overcharge dust mints");

        _mintAndApprove(user, previewAssets);
        vm.prank(user);
        uint256 assetsUsed = vault.mint(sharesToMint, user);

        assertEq(assetsUsed, previewAssets, "Actual assets used should match preview");
        assertEq(share.balanceOf(user), sharesToMint, "User should receive the requested dust shares");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), 0, "Dust mint should not accrue a rounded fee");
    }

    function test_depositFee_zeroFee_noFeeCharged() public {
        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(depositAmount, user);

        assertEq(sharesMinted, depositAmount, "No fee: shares should equal assets at 1:1 rate");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), 0, "No fee should be accrued");
    }

    function test_depositFee_claimFee() public {
        uint32 depositFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 expectedFee = depositAmount * depositFee / 1_000_000;
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), expectedFee);

        vm.prank(address(share));
        uint256 claimedAmount = vault.claimFee(NestVaultCoreTypes.Fees.Deposit, feeReceiver);

        assertEq(claimedAmount, expectedFee, "Claimed fee should match accrued fee");
        assertEq(asset.balanceOf(feeReceiver), expectedFee, "Fee receiver should get fee assets");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), 0, "Claimable should be zero after claim");
    }

    function test_setFee_deposit_exceedsMax_reverts() public {
        uint32 tooHigh = 200_001; // Just over 20% cap
        vm.expectRevert(Errors.InvalidFee.selector);
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(tooHigh, 0));
    }

    function test_depositFee_maxFee() public {
        uint32 maxFee = 200_000; // 20%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(maxFee, 0));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(depositAmount, user);

        uint256 expectedFee = depositAmount * maxFee / 1_000_000;
        uint256 expectedShares = depositAmount - expectedFee;
        assertEq(sharesMinted, expectedShares, "Max fee should take 20% of assets");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), expectedFee);
    }

    function test_depositFee_previewMatchesActual() public {
        uint32 depositFee = 15_000; // 1.5%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 depositAmount = 1_000e6;
        uint256 previewShares = vault.previewDeposit(depositAmount);

        _mintAndApprove(user, depositAmount);
        vm.prank(user);
        uint256 actualShares = vault.deposit(depositAmount, user);

        assertEq(actualShares, previewShares, "Actual shares should match preview");
    }

    function test_mintFee_previewMatchesActual() public {
        uint32 depositFee = 15_000; // 1.5%
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(depositFee, 0));

        uint256 sharesToMint = 985e6;
        uint256 previewAssets = vault.previewMint(sharesToMint);

        _mintAndApprove(user, previewAssets);
        vm.prank(user);
        uint256 actualAssets = vault.mint(sharesToMint, user);

        assertEq(actualAssets, previewAssets, "Actual assets should match preview");
        assertEq(share.balanceOf(user), sharesToMint, "User should have exact shares");
    }

    /*//////////////////////////////////////////////////////////////
                          REDEMPTION FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fulfillRedeemWithFee_reducesClaimableAssets() public {
        uint32 redemptionFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(redemptionFee, 0));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);

        uint256 assets = vault.fulfillRedeem(user, shares);

        uint256 grossAssets = shares;
        uint256 expectedFee = grossAssets * redemptionFee / 1_000_000;
        uint256 expectedNet = grossAssets - expectedFee;
        assertEq(assets, expectedNet, "FulfillRedeem should return net assets");
        assertEq(
            vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), expectedFee, "Redemption fee should be accrued"
        );
    }

    function test_fulfillRedeemWithFee_thenRedeem_userGetsNetAssets() public {
        uint32 redemptionFee = 20_000; // 2%
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(redemptionFee, 0));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        vault.fulfillRedeem(user, shares);

        uint256 grossAssets = shares;
        uint256 expectedFee = grossAssets * redemptionFee / 1_000_000;
        uint256 expectedNet = grossAssets - expectedFee;

        uint256 userBalanceBefore = asset.balanceOf(user);
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(shares, user, user);

        assertEq(assetsReceived, expectedNet, "User should receive net assets via redeem");
        assertEq(asset.balanceOf(user) - userBalanceBefore, expectedNet, "User asset balance should increase by net");
    }

    function test_fulfillRedeemWithFee_thenWithdraw_userGetsNetAssets() public {
        uint32 redemptionFee = 20_000; // 2%
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(redemptionFee, 0));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        vault.fulfillRedeem(user, shares);

        uint256 grossAssets = shares;
        uint256 expectedFee = grossAssets * redemptionFee / 1_000_000;
        uint256 expectedNet = grossAssets - expectedFee;

        uint256 userBalanceBefore = asset.balanceOf(user);
        vm.prank(user);
        vault.withdraw(expectedNet, user, user);

        assertEq(asset.balanceOf(user) - userBalanceBefore, expectedNet, "User should withdraw net assets");
    }

    function test_previewFulfillRedeem_returnsCorrectAmounts() public {
        uint32 redemptionFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(redemptionFee, 0));

        uint256 shares = 1_000e6;
        (uint256 postFeeAmount, uint256 feeAmount) = vault.previewFulfillRedeem(shares);

        uint256 grossAssets = shares;
        uint256 expectedFee = grossAssets * redemptionFee / 1_000_000;
        uint256 expectedNet = grossAssets - expectedFee;

        assertEq(postFeeAmount, expectedNet, "Preview post-fee should match expected net");
        assertEq(feeAmount, expectedFee, "Preview fee should match expected fee");
    }

    function test_redemptionFee_zeroFee_noFeeCharged() public {
        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);

        uint256 assets = vault.fulfillRedeem(user, shares);

        assertEq(assets, shares, "No fee: assets should equal shares at 1:1 rate");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), 0, "No fee should be accrued");
    }

    function test_redemptionFee_claimFee() public {
        uint32 redemptionFee = 10_000; // 1%
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(redemptionFee, 0));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        vault.fulfillRedeem(user, shares);

        uint256 expectedFee = shares * redemptionFee / 1_000_000;
        vm.prank(address(share));
        uint256 claimedAmount = vault.claimFee(NestVaultCoreTypes.Fees.Redemption, feeReceiver);

        assertEq(claimedAmount, expectedFee, "Claimed fee should match accrued fee");
        assertEq(asset.balanceOf(feeReceiver), expectedFee, "Fee receiver should get fee assets");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), 0, "Claimable should be zero after claim");
    }

    function test_setFee_redemption_exceedsMax_reverts() public {
        uint32 tooHigh = 200_001;
        vm.expectRevert(Errors.InvalidFee.selector);
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(tooHigh, 0));
    }

    function test_instantRedemptionFee_unchanged() public {
        uint32 instantFee = 5_000; // 0.5%
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(instantFee, 0));

        uint256 shares = 1_000e6;
        _prepareDeposit(user, shares);

        vm.prank(user);
        share.approve(address(vault), shares);

        vm.prank(user);
        (uint256 postFeeAmount, uint256 feeAmount) = vault.instantRedeem(shares, user, user);

        uint256 grossAssets = shares;
        uint256 expectedFee = grossAssets * instantFee / 1_000_000;
        assertEq(feeAmount, expectedFee, "InstantRedemption fee should still work");
        assertEq(postFeeAmount, grossAssets - expectedFee, "InstantRedemption post-fee should be correct");
        assertEq(
            vault.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption),
            0,
            "InstantRedemption fees should be sent to share, not accrued"
        );
    }

    function test_allThreeFees_independent() public {
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(10_000, 0));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(20_000, 0));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(5_000, 0));

        (uint32 dRate,) = vault.fees(NestVaultCoreTypes.Fees.Deposit);
        (uint32 rRate,) = vault.fees(NestVaultCoreTypes.Fees.Redemption);
        (uint32 iRate,) = vault.fees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(dRate, 10_000);
        assertEq(rRate, 20_000);
        assertEq(iRate, 5_000);

        (uint32 dMax,) = vault.maxFees(NestVaultCoreTypes.Fees.Deposit);
        (uint32 rMax,) = vault.maxFees(NestVaultCoreTypes.Fees.Redemption);
        (uint32 iMax,) = vault.maxFees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(dMax, 200_000);
        assertEq(rMax, 200_000);
        assertEq(iMax, 200_000);
    }

    /*//////////////////////////////////////////////////////////////
                        FLAT FEE DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositWithFlatFee_reducesSharesMinted() public {
        uint256 flatFee = 1e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, flatFee));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(depositAmount, user);

        uint256 expectedShares = depositAmount - flatFee;
        assertEq(sharesMinted, expectedShares, "Shares should reflect flat fee deduction");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), flatFee, "Flat fee should be accrued");
    }

    function test_depositWithFlatAndPercentageFee() public {
        uint256 flatFee = 100_000; // $0.10
        uint32 percentFee = 2_500; // 0.25%
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(percentFee, flatFee));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        uint256 sharesMinted = vault.deposit(depositAmount, user);

        uint256 expectedFee = flatFee + (depositAmount * percentFee / 1_000_000);
        uint256 expectedShares = depositAmount - expectedFee;
        assertEq(sharesMinted, expectedShares, "Shares should reflect combined fee");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Deposit), expectedFee, "Combined fee should be accrued");
    }

    function test_depositFlatFee_exceedsDeposit_reverts() public {
        uint256 flatFee = 1_001e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, flatFee));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);

        vm.prank(user);
        vm.expectRevert(Errors.ZeroShares.selector);
        vault.deposit(depositAmount, user);
    }

    function test_previewDeposit_withFlatFee_matchesActual() public {
        uint256 flatFee = 500_000;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(percentFee, flatFee));

        uint256 depositAmount = 1_000e6;
        uint256 previewShares = vault.previewDeposit(depositAmount);

        _mintAndApprove(user, depositAmount);
        vm.prank(user);
        uint256 actualShares = vault.deposit(depositAmount, user);

        assertEq(actualShares, previewShares, "Preview should match actual with flat + pct fee");
    }

    function test_previewDeposit_withFlatFee_returnsZeroWhenFeesConsumeAll() public {
        uint256 flatFee = 1_000e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, flatFee));

        uint256 previewShares = vault.previewDeposit(1_000e6);
        assertEq(previewShares, 0, "Preview should return 0 when fees consume entire deposit");
    }

    function test_previewMint_withFlatFee_returnsMinimalGross() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(percentFee, flatFee));

        uint256 sharesToMint = 989e6;
        uint256 previewAssets = vault.previewMint(sharesToMint);

        _mintAndApprove(user, previewAssets);
        vm.prank(user);
        uint256 actualAssets = vault.mint(sharesToMint, user);

        assertEq(actualAssets, previewAssets, "Actual should match preview");
        assertEq(share.balanceOf(user), sharesToMint, "User should receive exact shares");

        if (previewAssets > 1) {
            uint256 prevPreview = vault.previewDeposit(previewAssets - 1);
            assertLt(prevPreview, sharesToMint, "previewAssets should be minimal");
        }
    }

    function test_previewMint_withFlatFeeOnly_returnsCorrectGross() public {
        uint256 flatFee = 5e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, flatFee));

        uint256 sharesToMint = 100e6;
        uint256 previewAssets = vault.previewMint(sharesToMint);

        assertEq(previewAssets, sharesToMint + flatFee, "Gross should be shares + flat fee");

        _mintAndApprove(user, previewAssets);
        vm.prank(user);
        vault.mint(sharesToMint, user);
        assertEq(share.balanceOf(user), sharesToMint, "User should receive exact shares");
    }

    function test_previewMint_zeroShares_withFlatFee_returnsZero() public {
        uint256 flatFee = 5e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(10_000, flatFee));

        uint256 previewAssets = vault.previewMint(0);
        assertEq(previewAssets, 0, "previewMint(0) should return 0 even with flat fee");
    }

    function test_depositFlatFee_claimFee_combinedAmount() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(percentFee, flatFee));

        uint256 depositAmount = 1_000e6;
        _mintAndApprove(user, depositAmount);
        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 expectedFee = flatFee + (depositAmount * percentFee / 1_000_000);
        vm.prank(address(share));
        uint256 claimedAmount = vault.claimFee(NestVaultCoreTypes.Fees.Deposit, feeReceiver);

        assertEq(claimedAmount, expectedFee, "Claimed fee should include both flat and percentage");
        assertEq(asset.balanceOf(feeReceiver), expectedFee, "Fee receiver gets combined fee");
    }

    /*//////////////////////////////////////////////////////////////
                      FLAT FEE REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fulfillRedeemWithFlatFee_reducesClaimable() public {
        uint256 flatFee = 2e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(0, flatFee));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        uint256 assets = vault.fulfillRedeem(user, shares);

        uint256 expectedNet = shares - flatFee;
        assertEq(assets, expectedNet, "FulfillRedeem should deduct flat fee");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), flatFee, "Flat fee should be accrued");
    }

    function test_fulfillRedeemWithFlatAndPercentageFee() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 5_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        uint256 assets = vault.fulfillRedeem(user, shares);

        uint256 expectedFee = flatFee + (shares * percentFee / 1_000_000);
        uint256 expectedNet = shares - expectedFee;
        assertEq(assets, expectedNet, "FulfillRedeem should deduct combined fee");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), expectedFee, "Combined fee accrued");
    }

    function test_fulfillRedeem_flatFeeExceedsAssets_reverts() public {
        uint256 flatFee = 1_001e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(0, flatFee));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);

        vm.expectRevert(Errors.ZeroAssets.selector);
        vault.fulfillRedeem(user, shares);
    }

    function test_fulfillRedeem_flatFeeExceedsCap_reverts() public {
        uint256 flatFee = 250e6; // 25% of assets, exceeds 20% FEE_CAP
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(0, flatFee));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);

        vm.expectRevert(Errors.InvalidFee.selector);
        vault.fulfillRedeem(user, shares);
    }

    function test_previewFulfillRedeem_withFlatFee_matchesActual() public {
        uint256 flatFee = 500_000;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        (uint256 previewNet, uint256 previewFee) = vault.previewFulfillRedeem(shares);

        _prepareRedeem(user, shares);
        uint256 actualNet = vault.fulfillRedeem(user, shares);

        assertEq(actualNet, previewNet, "Preview net should match actual");
        assertEq(vault.claimableFees(NestVaultCoreTypes.Fees.Redemption), previewFee, "Preview fee should match actual");
    }

    function test_redemptionFlatFee_claimFee_combinedAmount() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        _prepareRedeem(user, shares);
        vault.fulfillRedeem(user, shares);

        uint256 expectedFee = flatFee + (shares * percentFee / 1_000_000);
        vm.prank(address(share));
        uint256 claimedAmount = vault.claimFee(NestVaultCoreTypes.Fees.Redemption, feeReceiver);

        assertEq(claimedAmount, expectedFee, "Claimed should include flat + percentage");
        assertEq(asset.balanceOf(feeReceiver), expectedFee, "Fee receiver gets combined fee");
    }

    /*//////////////////////////////////////////////////////////////
                    FLAT FEE INSTANT REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_instantRedeemWithFlatFee() public {
        uint256 flatFee = 1e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(0, flatFee));

        uint256 shares = 1_000e6;
        _prepareDeposit(user, shares);

        vm.prank(user);
        share.approve(address(vault), shares);

        vm.prank(user);
        (uint256 postFeeAmount, uint256 feeAmount) = vault.instantRedeem(shares, user, user);

        assertEq(feeAmount, flatFee, "Instant redeem flat fee should be correct");
        assertEq(postFeeAmount, shares - flatFee, "Post-fee amount should reflect flat fee");
        assertEq(
            vault.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption),
            0,
            "InstantRedemption fees should be sent to share, not accrued"
        );
    }

    function test_instantRedeemWithFlatAndPercentageFee() public {
        uint256 flatFee = 500_000;
        uint32 percentFee = 5_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        _prepareDeposit(user, shares);

        vm.prank(user);
        share.approve(address(vault), shares);

        vm.prank(user);
        (uint256 postFeeAmount, uint256 feeAmount) = vault.instantRedeem(shares, user, user);

        uint256 expectedFee = flatFee + (shares * percentFee / 1_000_000);
        assertEq(feeAmount, expectedFee, "Combined flat + pct fee should be correct");
        assertEq(postFeeAmount, shares - expectedFee, "Post-fee amount should reflect combined fee");
    }

    function test_instantRedeem_flatFeeExceedsAssets_reverts() public {
        uint256 flatFee = 1_001e6;
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(0, flatFee));

        uint256 shares = 1_000e6;
        _prepareDeposit(user, shares);

        vm.prank(user);
        share.approve(address(vault), shares);

        vm.prank(user);
        vm.expectRevert(Errors.ZeroAssets.selector);
        vault.instantRedeem(shares, user, user);
    }

    function test_previewInstantRedeem_withFlatFee_matchesActual() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 10_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        (uint256 previewNet, uint256 previewFee) = vault.previewInstantRedeem(shares);

        _prepareDeposit(user, shares);
        vm.prank(user);
        share.approve(address(vault), shares);
        vm.prank(user);
        (uint256 actualNet, uint256 actualFee) = vault.instantRedeem(shares, user, user);

        assertEq(actualNet, previewNet, "Preview net should match actual");
        assertEq(actualFee, previewFee, "Preview fee should match actual");
    }

    function test_instantRedemptionFlatFee_claimFee_combinedAmount() public {
        uint256 flatFee = 1e6;
        uint32 percentFee = 5_000;
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, flatFee));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(percentFee, flatFee));

        uint256 shares = 1_000e6;
        _prepareDeposit(user, shares);
        vm.prank(user);
        share.approve(address(vault), shares);
        vm.prank(user);
        vault.instantRedeem(shares, user, user);

        uint256 expectedFee = flatFee + (shares * percentFee / 1_000_000);
        // InstantRedemption fees go directly to share token, not claimable
        assertEq(
            vault.claimableFees(NestVaultCoreTypes.Fees.InstantRedemption),
            0,
            "InstantRedemption fees should be sent to share, not accrued"
        );
        assertEq(asset.balanceOf(address(share)), expectedFee, "Share token should receive combined fee");
    }

    /*//////////////////////////////////////////////////////////////
                      FLAT FEE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setFee_flatFee_revertsWhenMaxFlatFeeIsZero() public {
        // maxFees.flat defaults to 0, so any non-zero flat fee should revert
        vm.expectRevert(Errors.InvalidFee.selector);
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, 1));
    }

    function test_setFee_flatFee_exceedsMaxFlatFee_reverts() public {
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, 1e6));

        vm.expectRevert(Errors.InvalidFee.selector);
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, 1e6 + 1));
    }

    function test_setMaxFee_flatBelow_currentFlatFee_reverts() public {
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, 10e6));
        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, 5e6));

        vm.expectRevert(Errors.InvalidFee.selector);
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, 4e6));
    }

    function test_fees_defaultToZero() public {
        (uint32 dRate, uint256 dFlat) = vault.fees(NestVaultCoreTypes.Fees.Deposit);
        (uint32 rRate, uint256 rFlat) = vault.fees(NestVaultCoreTypes.Fees.Redemption);
        (uint32 iRate, uint256 iFlat) = vault.fees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(dRate, 0);
        assertEq(dFlat, 0);
        assertEq(rRate, 0);
        assertEq(rFlat, 0);
        assertEq(iRate, 0);
        assertEq(iFlat, 0);
    }

    function test_allThreeFlatFees_independent() public {
        vault.setMaxFee(NestVaultCoreTypes.Fees.Deposit, _fee(200_000, 10e6));
        vault.setMaxFee(NestVaultCoreTypes.Fees.Redemption, _fee(200_000, 20e6));
        vault.setMaxFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(200_000, 5e6));

        vault.setFee(NestVaultCoreTypes.Fees.Deposit, _fee(0, 1e6));
        vault.setFee(NestVaultCoreTypes.Fees.Redemption, _fee(0, 2e6));
        vault.setFee(NestVaultCoreTypes.Fees.InstantRedemption, _fee(0, 500_000));

        (, uint256 dFlat) = vault.fees(NestVaultCoreTypes.Fees.Deposit);
        (, uint256 rFlat) = vault.fees(NestVaultCoreTypes.Fees.Redemption);
        (, uint256 iFlat) = vault.fees(NestVaultCoreTypes.Fees.InstantRedemption);
        assertEq(dFlat, 1e6);
        assertEq(rFlat, 2e6);
        assertEq(iFlat, 500_000);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _fee(uint32 _rate, uint256 _flat) internal pure returns (NestVaultCoreTypes.Fee memory) {
        return NestVaultCoreTypes.Fee({rate: _rate, flat: _flat});
    }

    function _mintAndApprove(address _user, uint256 _amount) internal {
        asset.mint(_user, _amount);
        vm.prank(_user);
        asset.approve(address(vault), _amount);
    }

    function _prepareDeposit(address _user, uint256 _shares) internal {
        share.enter(_user, ERC20(address(asset)), 0, _user, _shares);
        asset.mint(address(share), _shares);
    }

    function _prepareRedeem(address _controller, uint256 _shares) internal {
        share.enter(_controller, ERC20(address(asset)), 0, _controller, _shares);

        vm.startPrank(_controller);
        share.approve(address(vault), _shares);
        vault.requestRedeem(_shares, _controller, _controller);
        vm.stopPrank();

        asset.mint(address(share), _shares);
    }

    function _deployContractAndProxy(
        bytes memory _oappBytecode,
        bytes memory _constructorArgs,
        bytes memory _initializeArgs
    ) internal returns (address addr) {
        bytes memory bytecode = bytes.concat(abi.encodePacked(_oappBytecode), _constructorArgs);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }

        return address(new TransparentUpgradeableProxy(addr, proxyAdmin, _initializeArgs));
    }
}
