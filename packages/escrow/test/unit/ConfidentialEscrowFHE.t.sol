// SPDX-License-Identifier: FSL-1.1-ALv2
pragma solidity ^0.8.25;

import {FHETestBase} from "@reineira-os/shared/test/FHETestBase.sol";
import {euint64, eaddress, InEuint64, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfidentialEscrow} from "../../contracts/core/ConfidentialEscrow.sol";
import {IEscrowEvents} from "@reineira-os/shared/contracts/interfaces/core/IEscrowEvents.sol";
import {MockConfidentialToken} from "../../contracts/mocks/MockConfidentialToken.sol";
import {MockConditionResolver} from "../../contracts/mocks/MockConditionResolver.sol";
import {MockConfidentialCoverageManager} from "../../contracts/mocks/MockConfidentialCoverageManager.sol";
import {EscrowCondition} from "../../contracts/extensions/EscrowCondition.sol";
import {EscrowLib} from "@reineira-os/shared/contracts/libraries/EscrowLib.sol";
import {FeeLib} from "@reineira-os/shared/contracts/libraries/FeeLib.sol";

contract ConfidentialEscrowFHETest is FHETestBase {
    ConfidentialEscrow public escrow;
    MockConfidentialToken public token;

    address public owner;
    address public escrowOwner;
    address public payer;
    address public attacker;
    address public feeRecipient;

    uint64 constant ESCROW_AMOUNT = 1000;
    uint64 constant PAYMENT_AMOUNT = 1000;
    uint64 constant FEE_BPS = 1000;

    function setUp() public {
        _initFHE();
        owner = _makeAccount("owner");
        escrowOwner = makeAddr("escrowOwner");
        payer = _makeAccount("payer");
        attacker = makeAddr("attacker");
        feeRecipient = makeAddr("feeRecipient");

        vm.startPrank(owner);
        token = new MockConfidentialToken();
        ConfidentialEscrow impl = new ConfidentialEscrow(address(0));
        escrow = ConfidentialEscrow(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(ConfidentialEscrow.initialize, (owner, address(token))))
            )
        );
        vm.stopPrank();
    }

    function _createEscrow() internal returns (uint256) {
        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);
        vm.prank(owner);
        return escrow.create(encOwner, encAmount, address(0), "");
    }

    function _createEscrowWithResolver(address resolver) internal returns (uint256) {
        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);
        vm.prank(owner);
        return escrow.create(encOwner, encAmount, resolver, "");
    }

    function _fundEscrow(uint256 escrowId) internal {
        vm.prank(owner);
        token.mintPlain(payer, PAYMENT_AMOUNT);
        vm.prank(payer);
        token.setOperator(address(escrow), uint48(block.timestamp + 86400));
        InEuint64 memory encPayment = createInEuint64(PAYMENT_AMOUNT, payer);
        vm.prank(payer);
        escrow.fund(escrowId, encPayment);
    }

    function _createAndFundEscrow() internal returns (uint256) {
        uint256 id = _createEscrow();
        _fundEscrow(id);
        return id;
    }

    function _createAndFundMultipleEscrows(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            _createEscrow();
        }
        vm.prank(owner);
        // safe: test loop counter, bounded by small test inputs
        // forge-lint: disable-next-line(unsafe-typecast)
        token.mintPlain(payer, PAYMENT_AMOUNT * uint64(count));
        vm.prank(payer);
        token.setOperator(address(escrow), uint48(block.timestamp + 86400));
        for (uint256 i = 0; i < count; i++) {
            InEuint64 memory encPayment = createInEuint64(PAYMENT_AMOUNT, payer);
            vm.prank(payer);
            escrow.fund(i, encPayment);
        }
    }

    function _deployCoverageManager() internal returns (MockConfidentialCoverageManager) {
        MockConfidentialCoverageManager mgr = new MockConfidentialCoverageManager(address(escrow));
        vm.prank(owner);
        escrow.setCoverageManager(address(mgr));
        return mgr;
    }

    function _setFee(MockConfidentialCoverageManager mgr, uint256 escrowId, address caller) internal {
        InEaddress memory encHolder = createInEaddress(escrowOwner, caller);
        InEuint64 memory encBps = createInEuint64(FEE_BPS, caller);
        vm.prank(caller);
        mgr.setFee(escrowId, encHolder, encBps, feeRecipient);
    }

    function test_create_createsEscrowWithEncryptedOwnerAndAmount() public {
        _createEscrow();
        assertTrue(escrow.exists(0));
        assertEq(escrow.total(), 1);
    }

    function test_create_emitsEscrowCreatedEvent() public {
        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowCreated(0);
        escrow.create(encOwner, encAmount, address(0), "");
    }

    function test_create_incrementsEscrowCounter() public {
        for (uint256 i = 0; i < 3; i++) {
            InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
            InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);
            vm.prank(owner);
            escrow.create(encOwner, encAmount, address(0), "");
        }
        assertEq(escrow.total(), 3);
    }

    function test_fund_acceptsPaymentForExistingEscrow() public {
        _createEscrow();
        vm.prank(owner);
        token.mintPlain(payer, PAYMENT_AMOUNT);
        vm.prank(payer);
        token.setOperator(address(escrow), uint48(block.timestamp + 86400));

        InEuint64 memory encPayment = createInEuint64(PAYMENT_AMOUNT, payer);

        vm.prank(payer);
        vm.expectEmit(true, true, false, false);
        emit IEscrowEvents.EscrowFunded(0, payer);
        escrow.fund(0, encPayment);
    }

    function test_fund_revertsForNonExistentEscrow() public {
        _createEscrow();
        vm.prank(owner);
        token.mintPlain(payer, PAYMENT_AMOUNT);
        vm.prank(payer);
        token.setOperator(address(escrow), uint48(block.timestamp + 86400));

        InEuint64 memory encPayment = createInEuint64(PAYMENT_AMOUNT, payer);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowDoesNotExist.selector, 999));
        escrow.fund(999, encPayment);
    }

    function test_redeem_emitsEscrowRedeemedEvent() public {
        _createAndFundEscrow();

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_redeem_revertsForNonExistentEscrow() public {
        _createAndFundEscrow();

        vm.prank(escrowOwner);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowDoesNotExist.selector, 999));
        escrow.redeem(999);
    }

    function test_redeem_allowsNonOwnerToCallRedeemTransfersZeroViaFHESelect() public {
        _createAndFundEscrow();

        vm.prank(payer);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_redeemMultiple_emitsEscrowBatchRedeemedEvent() public {
        _createAndFundMultipleEscrows(3);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }

    function test_redeemMultiple_revertsForEmptyArray() public {
        uint256[] memory empty = new uint256[](0);

        vm.prank(escrowOwner);
        vm.expectRevert(EscrowLib.EmptyArray.selector);
        escrow.redeemMultiple(empty);
    }

    function test_redeemMultiple_revertsWhenBatchExceedsMax() public {
        uint256 maxSize = escrow.MAX_BATCH_SIZE();
        uint256[] memory tooMany = new uint256[](maxSize + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = i;
        }

        vm.prank(escrowOwner);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.BatchSizeExceeded.selector, maxSize + 1, maxSize));
        escrow.redeemMultiple(tooMany);
    }

    function test_redeemMultiple_skipsNonExistentEscrowsSilently() public {
        _createAndFundMultipleEscrows(3);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 999;
        ids[2] = 1;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }

    function test_fundFrom_revertsForNonExistentEscrow() public {
        _createEscrow();

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowDoesNotExist.selector, 999));
        escrow.fundFrom(999, euint64.wrap(bytes32(uint256(12345))));
    }

    function test_fundFrom_revertsWithoutFHEPermission() public {
        _createEscrow();

        vm.prank(payer);
        vm.expectRevert();
        escrow.fundFrom(0, euint64.wrap(bytes32(uint256(12345))));
    }

    function test_view_returnsEncryptedValuesForEscrowGetters() public {
        _createEscrow();

        eaddress encOwnerResult = escrow.getOwner(0);
        euint64 encAmountResult = escrow.getAmount(0);
        escrow.getPaidAmount(0);
        escrow.getRedeemedStatus(0);

        assertTrue(eaddress.unwrap(encOwnerResult) != bytes32(0));
        assertTrue(euint64.unwrap(encAmountResult) != bytes32(0));
    }

    function test_condition_storesConditionResolverAddress() public {
        MockConditionResolver resolver = new MockConditionResolver();
        _createEscrowWithResolver(address(resolver));

        assertEq(escrow.getConditionResolver(0), address(resolver));
    }

    function test_condition_revertsRedeemWhenConditionNotMet() public {
        MockConditionResolver resolver = new MockConditionResolver();
        uint256 id = _createEscrowWithResolver(address(resolver));
        _fundEscrow(id);

        vm.prank(escrowOwner);
        vm.expectRevert(abi.encodeWithSelector(EscrowCondition.ConditionNotMet.selector, 0));
        escrow.redeem(0);
    }

    function test_condition_allowsRedeemWhenConditionMet() public {
        MockConditionResolver resolver = new MockConditionResolver();
        uint256 id = _createEscrowWithResolver(address(resolver));
        _fundEscrow(id);

        resolver.setCondition(0, true);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_condition_emitsConditionSetWhenCreatingWithResolver() public {
        MockConditionResolver resolver = new MockConditionResolver();

        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit EscrowCondition.ConditionSet(0, address(resolver));
        escrow.create(encOwner, encAmount, address(resolver), "");
    }

    function test_caller_storesEncryptedCallerDuringCreate() public {
        _createEscrow();

        eaddress callerHandle = escrow.getCaller(0);
        assertTrue(eaddress.unwrap(callerHandle) != bytes32(0));
    }

    function test_coverageManager_setsAndEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.CoverageManagerSet(attacker);
        escrow.setCoverageManager(attacker);
    }

    function test_coverageManager_revertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        escrow.setCoverageManager(attacker);
    }

    function test_coverageManager_revertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        escrow.setCoverageManager(address(0));
    }

    function test_fee_setsUnderwriterFeeStampsSlot() public {
        _createAndFundEscrow();
        MockConfidentialCoverageManager mgr = _deployCoverageManager();
        _setFee(mgr, 0, owner);

        (, address recipient, bool set) = escrow.getFee(0, uint8(FeeLib.FeeKind.Underwriter));
        assertEq(recipient, feeRecipient);
        assertTrue(set);
    }

    function test_fee_revertsForNonCoverageManagerCaller() public {
        _createAndFundEscrow();
        _deployCoverageManager();

        vm.prank(attacker);
        vm.expectRevert(EscrowLib.NotCoverageManager.selector);
        escrow.setUnderwriterFee(0, eaddress.wrap(bytes32(0)), euint64.wrap(bytes32(0)), attacker);
    }

    function test_fee_revertsForNonExistentEscrow() public {
        _createAndFundEscrow();
        MockConfidentialCoverageManager mgr = _deployCoverageManager();

        InEaddress memory encHolder = createInEaddress(escrowOwner, owner);
        InEuint64 memory encBps = createInEuint64(FEE_BPS, owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowDoesNotExist.selector, 999));
        mgr.setFee(999, encHolder, encBps, attacker);
    }

    function test_redeemWithFee_emitsEscrowRedeemedEvent() public {
        _createAndFundEscrow();
        MockConfidentialCoverageManager mgr = _deployCoverageManager();
        _setFee(mgr, 0, owner);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_redeemWithFee_allowsNonOwnerToCallRedeemTransfersZeroViaFHESelect() public {
        _createAndFundEscrow();
        MockConfidentialCoverageManager mgr = _deployCoverageManager();
        _setFee(mgr, 0, owner);

        vm.prank(payer);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_redeemMultipleWithFees_emitsEscrowBatchRedeemedEvent() public {
        MockConfidentialCoverageManager mgr = _deployCoverageManager();
        _createAndFundMultipleEscrows(3);
        for (uint256 i = 0; i < 3; i++) {
            _setFee(mgr, i, owner);
        }

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }

    function _createEscrowWithToken(address token_) internal returns (uint256) {
        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);
        bytes memory initData = abi.encode(encOwner, encAmount, token_);
        vm.prank(owner);
        return escrow.create(initData, address(0), "");
    }

    function _fundEscrowWith(uint256 escrowId, MockConfidentialToken token_) internal {
        vm.prank(owner);
        token_.mintPlain(payer, PAYMENT_AMOUNT);
        vm.prank(payer);
        token_.setOperator(address(escrow), uint48(block.timestamp + 86400));
        InEuint64 memory encPayment = createInEuint64(PAYMENT_AMOUNT, payer);
        vm.prank(payer);
        escrow.fund(escrowId, encPayment);
    }

    function test_initialize_allowsDefaultToken() public view {
        assertTrue(escrow.isAllowedToken(address(token)));
    }

    function test_create_typed_usesDefaultToken() public {
        _createEscrow();
        assertEq(escrow.paymentTokenOf(0), address(token));
    }

    function test_create_bytes_zeroToken_usesDefaultToken() public {
        _createEscrowWithToken(address(0));
        assertEq(escrow.paymentTokenOf(0), address(token));
    }

    function test_create_bytes_allowedToken_setsPaymentTokenOf() public {
        vm.prank(owner);
        MockConfidentialToken token2 = new MockConfidentialToken();
        vm.prank(owner);
        escrow.addAllowedToken(address(token2));

        _createEscrowWithToken(address(token2));
        assertEq(escrow.paymentTokenOf(0), address(token2));
    }

    function test_create_bytes_notAllowedToken_reverts() public {
        vm.prank(owner);
        MockConfidentialToken token2 = new MockConfidentialToken();

        InEaddress memory encOwner = createInEaddress(escrowOwner, owner);
        InEuint64 memory encAmount = createInEuint64(ESCROW_AMOUNT, owner);
        bytes memory initData = abi.encode(encOwner, encAmount, address(token2));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.TokenNotAllowed.selector, address(token2)));
        escrow.create(initData, address(0), "");
    }

    function test_addAllowedToken_revertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        escrow.addAllowedToken(attacker);
    }

    function test_addAllowedToken_emitsTokenAllowed() public {
        vm.prank(owner);
        MockConfidentialToken token2 = new MockConfidentialToken();
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.TokenAllowed(address(token2));
        escrow.addAllowedToken(address(token2));
        assertTrue(escrow.isAllowedToken(address(token2)));
    }

    function test_removeAllowedToken_emitsTokenRemoved() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.TokenRemoved(address(token));
        escrow.removeAllowedToken(address(token));
        assertFalse(escrow.isAllowedToken(address(token)));
    }

    function test_fundAndRedeem_useSelectedToken() public {
        vm.prank(owner);
        MockConfidentialToken token2 = new MockConfidentialToken();
        vm.prank(owner);
        escrow.addAllowedToken(address(token2));

        uint256 id = _createEscrowWithToken(address(token2));
        _fundEscrowWith(id, token2);

        vm.prank(escrowOwner);
        vm.expectEmit(true, false, false, false);
        emit IEscrowEvents.EscrowRedeemed(0);
        escrow.redeem(0);
    }

    function test_redeemMultiple_acrossDifferentTokens() public {
        vm.prank(owner);
        MockConfidentialToken token2 = new MockConfidentialToken();
        vm.prank(owner);
        escrow.addAllowedToken(address(token2));

        uint256 id0 = _createEscrow();
        _fundEscrow(id0);
        uint256 id1 = _createEscrowWithToken(address(token2));
        _fundEscrowWith(id1, token2);

        assertEq(escrow.paymentTokenOf(id0), address(token));
        assertEq(escrow.paymentTokenOf(id1), address(token2));

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.prank(escrowOwner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowEvents.EscrowBatchRedeemed(ids);
        escrow.redeemMultiple(ids);
    }
}
