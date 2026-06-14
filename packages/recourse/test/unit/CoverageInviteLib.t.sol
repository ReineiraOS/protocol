// SPDX-License-Identifier: FSL-1.1-ALv2
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CoverageInviteLib} from "@reineira-os/shared/contracts/libraries/CoverageInviteLib.sol";

/// @dev External wrapper so `vm.expectRevert` observes the library at a call boundary.
contract CoverageInviteLibHarness {
    function typehash() external pure returns (bytes32) {
        return CoverageInviteLib.COVERAGE_INVITE_TYPEHASH;
    }

    function hashStruct(CoverageInviteLib.CoverageInvite memory invite) external pure returns (bytes32) {
        return CoverageInviteLib.hashStruct(invite);
    }

    function digest(
        bytes32 domainSeparator,
        CoverageInviteLib.CoverageInvite memory invite
    ) external pure returns (bytes32) {
        return CoverageInviteLib.digest(domainSeparator, invite);
    }

    function recoverSigner(
        bytes32 domainSeparator,
        CoverageInviteLib.CoverageInvite memory invite,
        bytes memory signature
    ) external pure returns (address) {
        return CoverageInviteLib.recoverSigner(domainSeparator, invite, signature);
    }
}

contract CoverageInviteLibTest is Test {
    CoverageInviteLibHarness internal lib;

    bytes32 internal domainSeparator;
    address internal pool;
    address internal invitee;
    address internal signer;
    uint256 internal signerKey;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        lib = new CoverageInviteLibHarness();

        pool = makeAddr("pool");
        invitee = makeAddr("invitee");
        (signer, signerKey) = makeAddrAndKey("manager");

        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("Reineira CoverageInvite")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function _invite() internal view returns (CoverageInviteLib.CoverageInvite memory) {
        return
            CoverageInviteLib.CoverageInvite({
                pool: pool,
                invitee: invitee,
                maxUses: 5,
                deadline: block.timestamp + 30 days,
                inviteId: 1
            });
    }

    function _sign(
        CoverageInviteLib.CoverageInvite memory invite,
        bytes32 ds,
        uint256 key
    ) internal view returns (bytes memory) {
        bytes32 d = lib.digest(ds, invite);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, d);
        return abi.encodePacked(r, s, v);
    }

    function test_typehash_isCanonical() public view {
        bytes32 expected = keccak256(
            "CoverageInvite(address pool,address invitee,uint256 maxUses,uint256 deadline,uint256 inviteId)"
        );
        assertEq(lib.typehash(), expected);
    }

    function test_hashStruct_deterministic() public view {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes32 a = lib.hashStruct(inv);
        bytes32 b = lib.hashStruct(inv);
        assertEq(a, b);
        assertTrue(a != bytes32(0));
    }

    function test_digest_changesWhenAnyFieldChanges() public {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes32 base = lib.digest(domainSeparator, inv);

        CoverageInviteLib.CoverageInvite memory mutated = inv;
        mutated.inviteId = 2;
        assertTrue(lib.digest(domainSeparator, mutated) != base);

        mutated = inv;
        mutated.invitee = makeAddr("other");
        assertTrue(lib.digest(domainSeparator, mutated) != base);

        mutated = inv;
        mutated.pool = makeAddr("otherPool");
        assertTrue(lib.digest(domainSeparator, mutated) != base);

        mutated = inv;
        mutated.maxUses = 6;
        assertTrue(lib.digest(domainSeparator, mutated) != base);

        mutated = inv;
        mutated.deadline = inv.deadline + 1;
        assertTrue(lib.digest(domainSeparator, mutated) != base);
    }

    function test_digest_changesWithDomainSeparator() public view {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes32 a = lib.digest(domainSeparator, inv);
        bytes32 other = keccak256("different");
        bytes32 b = lib.digest(other, inv);
        assertTrue(a != b);
    }

    function test_recoverSigner_recoversCorrectAddress() public view {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes memory sig = _sign(inv, domainSeparator, signerKey);
        assertEq(lib.recoverSigner(domainSeparator, inv, sig), signer);
    }

    function test_recoverSigner_wrongDomainGivesDifferentAddress() public view {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes memory sig = _sign(inv, domainSeparator, signerKey);
        bytes32 otherDs = keccak256("different-domain");
        address recovered = lib.recoverSigner(otherDs, inv, sig);
        assertTrue(recovered != signer);
    }

    function test_recoverSigner_tamperedInviteGivesDifferentAddress() public view {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes memory sig = _sign(inv, domainSeparator, signerKey);

        CoverageInviteLib.CoverageInvite memory tampered = inv;
        tampered.maxUses = 1_000_000; // attacker bumps usage cap
        address recovered = lib.recoverSigner(domainSeparator, tampered, sig);
        assertTrue(recovered != signer);
    }

    function test_recoverSigner_revertsOnMalformedSignature() public {
        CoverageInviteLib.CoverageInvite memory inv = _invite();
        bytes memory badSig = hex"deadbeef"; // wrong length
        vm.expectRevert();
        lib.recoverSigner(domainSeparator, inv, badSig);
    }
}
