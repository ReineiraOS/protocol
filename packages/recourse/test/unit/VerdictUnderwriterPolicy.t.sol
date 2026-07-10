// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {VerdictUnderwriterPolicy} from "../../contracts/plugins/VerdictUnderwriterPolicy.sol";
import {IUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IUnderwriterPolicy.sol";

contract VerdictUnderwriterPolicyTest is Test {
    VerdictUnderwriterPolicy policy;
    uint256 signerPk = 0xA11CE;
    uint256 attackerPk = 0xBADBAD;
    address signer;
    uint256 freshness = 1 days;

    function setUp() public {
        vm.warp(1_000_000);
        signer = vm.addr(signerPk);
        policy = new VerdictUnderwriterPolicy(signer, freshness);
    }

    function _breach(uint256 coverageId, uint256 nonce) internal view returns (VerdictUnderwriterPolicy.Verdict memory v) {
        v = VerdictUnderwriterPolicy.Verdict({
            coverageId: coverageId,
            breach: true,
            amount: 100_000,
            nonce: nonce,
            issuedAt: block.timestamp,
            termsHash: keccak256("terms"),
            triggerSpecHash: keccak256("deadline-rule")
        });
    }

    function _proof(VerdictUnderwriterPolicy.Verdict memory v, uint256 pk) internal view returns (bytes memory) {
        (uint8 yv, bytes32 r, bytes32 s) = vm.sign(pk, policy.hashVerdict(v));
        return abi.encode(v, abi.encodePacked(r, s, yv));
    }

    function test_judge_validSignedBreach_returnsTrueAndMarksNonce() public {
        bytes memory proof = _proof(_breach(7, 1), signerPk);
        assertTrue(policy.judge(7, proof));
        assertTrue(policy.usedNonce(1));
    }

    function test_judge_wrongSigner_reverts() public {
        bytes memory proof = _proof(_breach(7, 1), attackerPk);
        vm.expectRevert(VerdictUnderwriterPolicy.InvalidSigner.selector);
        policy.judge(7, proof);
    }

    function test_judge_replayedNonce_reverts() public {
        bytes memory proof = _proof(_breach(7, 1), signerPk);
        policy.judge(7, proof);
        vm.expectRevert(VerdictUnderwriterPolicy.NonceAlreadyUsed.selector);
        policy.judge(7, proof);
    }

    function test_judge_staleVerdict_reverts() public {
        VerdictUnderwriterPolicy.Verdict memory v = _breach(7, 1);
        v.issuedAt = block.timestamp - freshness - 1;
        bytes memory proof = _proof(v, signerPk);
        vm.expectRevert(VerdictUnderwriterPolicy.StaleVerdict.selector);
        policy.judge(7, proof);
    }

    function test_judge_coverageIdMismatch_reverts() public {
        bytes memory proof = _proof(_breach(7, 1), signerPk);
        vm.expectRevert(VerdictUnderwriterPolicy.CoverageMismatch.selector);
        policy.judge(8, proof);
    }

    function test_judge_noBreach_returnsFalse() public {
        VerdictUnderwriterPolicy.Verdict memory v = _breach(7, 1);
        v.breach = false;
        bytes memory proof = _proof(v, signerPk);
        assertFalse(policy.judge(7, proof));
    }

    function test_supportsInterface_underwriterPolicy() public view {
        assertTrue(policy.supportsInterface(type(IUnderwriterPolicy).interfaceId));
    }
}
