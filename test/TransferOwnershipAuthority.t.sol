// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransferOwnership} from "script/setup/TransferOwnership.s.sol";

contract TransferOwnershipHarness is TransferOwnership {
    function pick(string memory label, address configured, address live) external view returns (address) {
        return _pickAuthority(label, configured, live);
    }
}

contract TransferOwnershipAuthorityTest is Test {
    function test_pickAuthority() public {
        TransferOwnershipHarness h = new TransferOwnershipHarness();
        address ra1 = makeAddr("ra1");
        address ra2 = makeAddr("ra2");
        vm.etch(ra2, hex"00");

        assertEq(h.pick("vault", address(0), ra1), ra1); // no configured -> live
        assertEq(h.pick("vault", ra2, address(0)), ra2); // no live anchor -> configured
        assertEq(h.pick("vault", ra2, ra2), ra2); // agreement -> configured

        vm.expectRevert(); // mismatch without opt-in
        h.pick("vault", ra2, ra1);

        vm.setEnv("ALLOW_AUTHORITY_MISMATCH", "true");
        assertEq(h.pick("vault", ra2, ra1), ra2); // opt-in -> configured
    }
}
