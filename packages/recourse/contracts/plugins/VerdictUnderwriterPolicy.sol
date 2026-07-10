// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IUnderwriterPolicy} from "@reineira-os/shared/contracts/interfaces/plugins/IUnderwriterPolicy.sol";

contract VerdictUnderwriterPolicy is IUnderwriterPolicy, ERC165, EIP712 {
    struct Verdict {
        uint256 coverageId;
        bool breach;
        uint256 amount;
        uint256 nonce;
        uint256 issuedAt;
        bytes32 termsHash;
        bytes32 triggerSpecHash;
    }

    bytes32 private constant VERDICT_TYPEHASH = keccak256(
        "Verdict(uint256 coverageId,bool breach,uint256 amount,uint256 nonce,uint256 issuedAt,bytes32 termsHash,bytes32 triggerSpecHash)"
    );

    address public immutable trustedSigner;
    uint256 public immutable freshnessWindow;
    mapping(uint256 => bool) public usedNonce;
    uint256 private constant RISK_SCORE = 500;

    error CoverageMismatch();
    error StaleVerdict();
    error NonceAlreadyUsed();
    error InvalidSigner();

    constructor(address trustedSigner_, uint256 freshnessWindow_) EIP712("ReineiraVerdict", "1") {
        trustedSigner = trustedSigner_;
        freshnessWindow = freshnessWindow_;
    }

    function hashVerdict(Verdict memory v) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    VERDICT_TYPEHASH, v.coverageId, v.breach, v.amount, v.nonce, v.issuedAt, v.termsHash, v.triggerSpecHash
                )
            )
        );
    }

    function judge(uint256 coverageId, bytes calldata disputeProof) external returns (bool) {
        (Verdict memory v, bytes memory signature) = abi.decode(disputeProof, (Verdict, bytes));
        if (v.coverageId != coverageId) revert CoverageMismatch();
        if (!v.breach) return false;
        if (block.timestamp > v.issuedAt + freshnessWindow) revert StaleVerdict();
        if (usedNonce[v.nonce]) revert NonceAlreadyUsed();
        if (ECDSA.recover(hashVerdict(v), signature) != trustedSigner) revert InvalidSigner();
        usedNonce[v.nonce] = true;
        return true;
    }

    function evaluateRisk(uint256, bytes calldata) external pure returns (uint256) {
        return RISK_SCORE;
    }

    function onPolicySet(uint256, bytes calldata) external {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IUnderwriterPolicy).interfaceId || super.supportsInterface(interfaceId);
    }
}
