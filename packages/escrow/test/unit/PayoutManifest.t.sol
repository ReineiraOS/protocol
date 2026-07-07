// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InEuint64, EncryptedInput} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {PayoutManifest} from "../../contracts/core/PayoutManifest.sol";
import {IPayoutManifest} from "../../contracts/interfaces/core/IPayoutManifest.sol";
import {MockEscrow} from "../../contracts/mocks/MockEscrow.sol";
import {MockReentrantEscrow} from "../../contracts/mocks/MockReentrantEscrow.sol";

address constant TASK_MANAGER_ADDRESS = 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9;

/// @notice Minimal TaskManager mock for FHEMeta.asEuint64 and FHE.allow
contract MockTaskManager {
    function verifyInput(EncryptedInput memory, address) external pure returns (uint256) {
        return 12345;
    }

    function allow(uint256, address) external pure {}
}

contract PayoutManifestTest is Test {
    PayoutManifest public manifest;
    MockEscrow public escrow;

    address public owner;
    address public gate0Caller;
    address public gate1Caller;
    address public user;

    uint256 constant ESCROW_ID = 42;
    bytes32 constant INVOCATION_ID = keccak256("test-invocation");

    function setUp() public {
        // Deploy minimal TaskManager mock at hardcoded address for FHE operations
        vm.etch(TASK_MANAGER_ADDRESS, type(MockTaskManager).runtimeCode);

        owner = makeAddr("owner");
        gate0Caller = makeAddr("gate0Caller");
        gate1Caller = makeAddr("gate1Caller");
        user = makeAddr("user");

        vm.startPrank(owner);
        escrow = new MockEscrow();
        PayoutManifest impl = new PayoutManifest(address(0));
        manifest = PayoutManifest(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(PayoutManifest.initialize, (owner, address(escrow))))
            )
        );
        manifest.setGateCaller(0, gate0Caller);
        manifest.setGateCaller(1, gate1Caller);
        vm.stopPrank();
    }

    // ── Helpers ───────────────────────────────────────────────────

    function _inEuint64(uint64 value) internal pure returns (InEuint64 memory) {
        return InEuint64({ctHash: uint256(value), securityZone: 0, utype: 5, signature: ""});
    }

    function _makeLines(
        uint64 amount0,
        address recipient0,
        uint8 mask0,
        uint64 amount1,
        address recipient1,
        uint8 mask1,
        uint64 amount2,
        address recipient2,
        uint8 mask2
    ) internal pure returns (IPayoutManifest.PayoutLineInput[] memory lines) {
        lines = new IPayoutManifest.PayoutLineInput[](3);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(amount0), recipient0, mask0);
        lines[1] = IPayoutManifest.PayoutLineInput(_inEuint64(amount1), recipient1, mask1);
        lines[2] = IPayoutManifest.PayoutLineInput(_inEuint64(amount2), recipient2, mask2);
    }

    function _registerSchema3() internal {
        address r0 = makeAddr("recipient0");
        address r1 = makeAddr("recipient1");
        address r2 = makeAddr("recipient2");

        IPayoutManifest.PayoutLineInput[] memory lines = _makeLines(
            100,
            r0,
            1, // gate 0 only
            200,
            r1,
            2, // gate 1 only
            300,
            r2,
            3 // both gates
        );

        vm.prank(owner);
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    // ── Deployment / Init ─────────────────────────────────────────

    function test_deployment_setsCorrectOwnerAndEscrow() public view {
        assertEq(manifest.owner(), owner);
        assertEq(manifest.escrow(), address(escrow));
    }

    function test_deployment_revertsWithZeroEscrow() public {
        PayoutManifest impl = new PayoutManifest(address(0));
        vm.prank(owner);
        vm.expectRevert(IPayoutManifest.InvalidEscrow.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(PayoutManifest.initialize, (owner, address(0))));
    }

    function test_setEscrow_updatesEscrow() public {
        MockEscrow newEscrow = new MockEscrow();
        vm.prank(owner);
        manifest.setEscrow(address(newEscrow));
        assertEq(manifest.escrow(), address(newEscrow));
    }

    function test_setEscrow_revertsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IPayoutManifest.InvalidEscrow.selector);
        manifest.setEscrow(address(0));
    }

    function test_setEscrow_revertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        manifest.setEscrow(address(escrow));
    }

    function test_setGateCaller_updatesCaller() public {
        vm.prank(owner);
        manifest.setGateCaller(0, user);
        assertEq(manifest.gateCaller(0), user);
    }

    function test_setGateCaller_revertsWithInvalidGateId() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.InvalidGateId.selector, 5));
        manifest.setGateCaller(5, user);
    }

    // ── Schema Registration ───────────────────────────────────────

    function test_registerSchema_emitsEvent() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 1);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IPayoutManifest.SchemaRegistered(ESCROW_ID, INVOCATION_ID, 1);
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_storesLines() public {
        _registerSchema3();

        assertTrue(manifest.schemaExists(ESCROW_ID, INVOCATION_ID));
        assertEq(manifest.getSchemaLineCount(ESCROW_ID, INVOCATION_ID), 3);

        (uint256 amount0, address recipient0, uint8 mask0) = manifest.getSchemaLine(ESCROW_ID, INVOCATION_ID, 0);
        assertEq(recipient0, makeAddr("recipient0"));
        assertEq(mask0, 1);
        assertEq(amount0, 12345); // dummy handle from MockTaskManager

        (, address recipient1, uint8 mask1) = manifest.getSchemaLine(ESCROW_ID, INVOCATION_ID, 1);
        assertEq(recipient1, makeAddr("recipient1"));
        assertEq(mask1, 2);

        (, address recipient2, uint8 mask2) = manifest.getSchemaLine(ESCROW_ID, INVOCATION_ID, 2);
        assertEq(recipient2, makeAddr("recipient2"));
        assertEq(mask2, 3);
    }

    function test_registerSchema_revertsWhenNotOwner() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 1);

        vm.prank(user);
        vm.expectRevert();
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_revertsWithEmptySchema() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](0);

        vm.prank(owner);
        vm.expectRevert(IPayoutManifest.EmptySchema.selector);
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_revertsWithZeroRecipient() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), address(0), 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.InvalidRecipient.selector, 0));
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_revertsWithInvalidGateMask() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.InvalidGateMask.selector, 0, 0));
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_revertsWithGateMaskExceedingTwoGates() public {
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 5);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.InvalidGateMask.selector, 0, 5));
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    function test_registerSchema_revertsIfAlreadyExists() public {
        _registerSchema3();

        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.SchemaAlreadyExists.selector, ESCROW_ID, INVOCATION_ID));
        manifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);
    }

    // ── Two-gate release table (4 cells) ──────────────────────────

    function test_gate0Only_releasesGate0Lines() public {
        _registerSchema3();

        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);

        assertEq(escrow.getReleaseCallCount(), 1);
        MockEscrow.ReleaseCall memory call = escrow.getReleaseCall(0);
        assertEq(call.escrowId, ESCROW_ID);
        assertEq(call.recipient, makeAddr("recipient0"));

        assertTrue(manifest.isGateConsumed(INVOCATION_ID, 0));
        assertFalse(manifest.isGateConsumed(INVOCATION_ID, 1));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 0));
        assertFalse(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 1));
        assertFalse(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 2));
    }

    function test_gate1Only_releasesGate1Lines() public {
        _registerSchema3();

        vm.prank(gate1Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 1);

        assertEq(escrow.getReleaseCallCount(), 1);
        MockEscrow.ReleaseCall memory call = escrow.getReleaseCall(0);
        assertEq(call.escrowId, ESCROW_ID);
        assertEq(call.recipient, makeAddr("recipient1"));

        assertFalse(manifest.isGateConsumed(INVOCATION_ID, 0));
        assertTrue(manifest.isGateConsumed(INVOCATION_ID, 1));
        assertFalse(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 0));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 1));
        assertFalse(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 2));
    }

    function test_bothGates_gate0ThenGate1_releasesAllLines() public {
        _registerSchema3();

        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);

        vm.prank(gate1Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 1);

        assertEq(escrow.getReleaseCallCount(), 3);
        assertEq(escrow.getReleaseCall(0).recipient, makeAddr("recipient0"));
        assertEq(escrow.getReleaseCall(1).recipient, makeAddr("recipient1"));
        assertEq(escrow.getReleaseCall(2).recipient, makeAddr("recipient2"));

        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 0));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 1));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 2));
    }

    function test_bothGates_gate1ThenGate0_releasesAllLines() public {
        _registerSchema3();

        vm.prank(gate1Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 1);

        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);

        assertEq(escrow.getReleaseCallCount(), 3);
        // order depends on firing order: gate1 fires first => recipient1 first
        assertEq(escrow.getReleaseCall(0).recipient, makeAddr("recipient1"));
        assertEq(escrow.getReleaseCall(1).recipient, makeAddr("recipient0"));
        assertEq(escrow.getReleaseCall(2).recipient, makeAddr("recipient2"));

        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 0));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 1));
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 2));
    }

    // ── Failure modes ─────────────────────────────────────────────

    function test_gateFire_revertsIfAlreadyConsumed() public {
        _registerSchema3();

        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);

        vm.prank(gate0Caller);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.GateAlreadyConsumed.selector, INVOCATION_ID, 0));
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
    }

    function test_gateFire_revertsIfUnauthorizedCaller() public {
        _registerSchema3();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.UnauthorizedGateCaller.selector, 0, user));
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
    }

    function test_gateFire_revertsIfSchemaNotFound() public {
        vm.prank(gate0Caller);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.SchemaNotFound.selector, ESCROW_ID, INVOCATION_ID));
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
    }

    function test_gateFire_revertsWithInvalidGateId() public {
        vm.prank(gate0Caller);
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.InvalidGateId.selector, 5));
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 5);
    }

    function test_gateFire_doesNotReReleaseAlreadyReleasedLines() public {
        _registerSchema3();

        // Fire both gates
        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
        vm.prank(gate1Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 1);

        // Total 3 releases
        assertEq(escrow.getReleaseCallCount(), 3);

        // Verify line 0 not released again (escrow only has 3 calls)
        assertTrue(manifest.isLineReleased(ESCROW_ID, INVOCATION_ID, 0));
    }

    function test_reentrancy_protected() public {
        // Deploy manifest with reentrant escrow
        MockReentrantEscrow reentrantEscrow = new MockReentrantEscrow();

        vm.startPrank(owner);
        PayoutManifest impl = new PayoutManifest(address(0));
        PayoutManifest reentrantManifest = PayoutManifest(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(PayoutManifest.initialize, (owner, address(reentrantEscrow)))
                )
            )
        );
        reentrantManifest.setGateCaller(0, gate0Caller);
        vm.stopPrank();

        reentrantEscrow.setManifest(address(reentrantManifest));
        reentrantEscrow.setReentrantParams(ESCROW_ID, INVOCATION_ID, 0);

        // Register a simple schema
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(100), makeAddr("recipient0"), 1);
        vm.prank(owner);
        reentrantManifest.registerSchema(ESCROW_ID, INVOCATION_ID, lines);

        // Attempt reentrant gate fire
        vm.prank(gate0Caller);
        vm.expectRevert();
        reentrantManifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
    }

    function test_gateFire_emitsEvents() public {
        _registerSchema3();

        vm.prank(gate0Caller);
        vm.expectEmit(true, true, true, true);
        emit IPayoutManifest.LineReleased(ESCROW_ID, INVOCATION_ID, 0, makeAddr("recipient0"));
        vm.expectEmit(true, true, true, false);
        emit IPayoutManifest.GateFired(ESCROW_ID, INVOCATION_ID, 0);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);
    }

    function test_differentInvocations_areIndependent() public {
        _registerSchema3();

        bytes32 invocation2 = keccak256("test-invocation-2");
        IPayoutManifest.PayoutLineInput[] memory lines = new IPayoutManifest.PayoutLineInput[](1);
        lines[0] = IPayoutManifest.PayoutLineInput(_inEuint64(500), makeAddr("recipient4"), 1);
        vm.prank(owner);
        manifest.registerSchema(ESCROW_ID, invocation2, lines);

        // Fire gate 0 on invocation 1
        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, INVOCATION_ID, 0);

        // Invocation 2 gate 0 should still be available
        vm.prank(gate0Caller);
        manifest.onGateFired(ESCROW_ID, invocation2, 0);

        assertEq(escrow.getReleaseCallCount(), 2);
        assertTrue(manifest.isGateConsumed(INVOCATION_ID, 0));
        assertTrue(manifest.isGateConsumed(invocation2, 0));
    }

    function test_getSchemaLine_revertsForMissingSchema() public {
        vm.expectRevert(abi.encodeWithSelector(IPayoutManifest.SchemaNotFound.selector, 999, INVOCATION_ID));
        manifest.getSchemaLine(999, INVOCATION_ID, 0);
    }

    function test_getSchemaLine_revertsForOutOfBoundsIndex() public {
        _registerSchema3();
        vm.expectRevert(IPayoutManifest.InvalidSchemaLength.selector);
        manifest.getSchemaLine(ESCROW_ID, INVOCATION_ID, 10);
    }
}
