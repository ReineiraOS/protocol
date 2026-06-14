// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Reineira Labs Limited All rights reserved.
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title CoverageInviteLib
/// @notice EIP-712 helpers for closed-pool coverage-purchase admission. The voucher
///         authorizes a public submitter (`invitee`) to purchase coverage from a
///         specific pool, with bounded `maxUses` and a `deadline`. Tracking the per-
///         invite usage count and revocation is the calling contract's responsibility;
///         this library is purely cryptographic.
///
///         Use the returned `digest` as the on-chain key for usage tracking — any
///         change to any signed field produces a different digest, so collisions are
///         impossible across distinct invites.
library CoverageInviteLib {
    struct CoverageInvite {
        address pool;
        address invitee;
        uint256 maxUses;
        uint256 deadline;
        uint256 inviteId;
    }

    /// @notice EIP-712 typeHash for the `CoverageInvite` struct.
    bytes32 internal constant COVERAGE_INVITE_TYPEHASH =
        keccak256("CoverageInvite(address pool,address invitee,uint256 maxUses,uint256 deadline,uint256 inviteId)");

    /// @notice Compute the EIP-712 struct hash of a CoverageInvite.
    function hashStruct(CoverageInvite memory invite) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    COVERAGE_INVITE_TYPEHASH,
                    invite.pool,
                    invite.invitee,
                    invite.maxUses,
                    invite.deadline,
                    invite.inviteId
                )
            );
    }

    /// @notice Compute the full EIP-712 typed-data digest under `domainSeparator`.
    function digest(bytes32 domainSeparator, CoverageInvite memory invite) internal pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(domainSeparator, hashStruct(invite));
    }

    /// @notice Recover the signer of `signature` over the typed-data digest.
    /// @dev Reverts on malformed signatures (wrong length, invalid `s`).
    function recoverSigner(
        bytes32 domainSeparator,
        CoverageInvite memory invite,
        bytes memory signature
    ) internal pure returns (address) {
        return ECDSA.recover(digest(domainSeparator, invite), signature);
    }
}
