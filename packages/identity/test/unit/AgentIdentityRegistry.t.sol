// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentIdentityRegistry} from "../../contracts/core/AgentIdentityRegistry.sol";
import {IAgentIdentityRegistry} from "../../contracts/interfaces/core/IAgentIdentityRegistry.sol";

contract AgentIdentityRegistryTest is Test {
    AgentIdentityRegistry public registry;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");

    function setUp() public {
        vm.startPrank(owner);
        AgentIdentityRegistry impl = new AgentIdentityRegistry(address(0));
        bytes memory initData = abi.encodeCall(AgentIdentityRegistry.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = AgentIdentityRegistry(address(proxy));
        vm.stopPrank();
    }

    function _computeDigest(
        uint256 agentId,
        address newWallet,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Reineira Agent Identity")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 nonce,uint256 deadline)"),
                agentId,
                newWallet,
                nonce,
                deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // --- registration ---

    function test_register_withURIAndMetadata() public {
        IAgentIdentityRegistry.MetadataEntry[] memory meta = new IAgentIdentityRegistry.MetadataEntry[](1);
        meta[0] = IAgentIdentityRegistry.MetadataEntry({metadataKey: "role", metadataValue: abi.encode("executor")});

        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent1", meta);

        assertEq(id, 0);
        assertEq(registry.ownerOf(0), user1);
        assertEq(registry.tokenURI(0), "ipfs://agent1");
        assertEq(registry.agentCount(), 1);
    }

    function test_register_withURI() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent2");

        assertEq(id, 0);
        assertEq(registry.ownerOf(0), user1);
        assertEq(registry.tokenURI(0), "ipfs://agent2");
    }

    function test_register_withoutURI() public {
        vm.prank(user1);
        uint256 id = registry.register();

        assertEq(id, 0);
        assertEq(registry.ownerOf(0), user1);
        assertEq(registry.tokenURI(0), "");
    }

    function test_register_emitsRegisteredEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, true, true);
        emit IAgentIdentityRegistry.Registered(0, "ipfs://agent1", user1);
        registry.register("ipfs://agent1");
    }

    function test_register_emitsMetadataSetForAgentWallet() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IAgentIdentityRegistry.MetadataSet(0, "agentWallet", "agentWallet", abi.encode(user1));
        registry.register("ipfs://agent1");
    }

    function test_register_multipleIncrementsAgentCount() public {
        vm.prank(user1);
        registry.register("ipfs://a");
        vm.prank(user2);
        registry.register("ipfs://b");
        assertEq(registry.agentCount(), 2);
    }

    // --- URI ---

    function test_setAgentURI_updatesURI() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://old");

        vm.prank(user1);
        registry.setAgentURI(id, "ipfs://new");
        assertEq(registry.tokenURI(id), "ipfs://new");
    }

    function test_setAgentURI_revertsForNonOwner() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://old");

        vm.prank(user2);
        vm.expectRevert(IAgentIdentityRegistry.NotAgentOwner.selector);
        registry.setAgentURI(id, "ipfs://new");
    }

    function test_setAgentURI_revertsForNonExistentAgent() public {
        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.AgentNotFound.selector);
        registry.setAgentURI(99, "ipfs://new");
    }

    function test_setAgentURI_emitsEvent() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://old");

        vm.prank(user1);
        vm.expectEmit(true, false, true, true);
        emit IAgentIdentityRegistry.URIUpdated(id, "ipfs://new", user1);
        registry.setAgentURI(id, "ipfs://new");
    }

    // --- metadata ---

    function test_setMetadata_storesValue() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user1);
        registry.setMetadata(id, "version", abi.encode("1.0"));

        assertEq(registry.getMetadata(id, "version"), abi.encode("1.0"));
    }

    function test_setMetadata_revertsForReservedKey() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.ReservedMetadataKey.selector);
        registry.setMetadata(id, "agentWallet", abi.encode(address(1)));
    }

    function test_setMetadata_revertsForNonOwner() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user2);
        vm.expectRevert(IAgentIdentityRegistry.NotAgentOwner.selector);
        registry.setMetadata(id, "key", abi.encode("value"));
    }

    function test_setMetadata_emitsEvent() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IAgentIdentityRegistry.MetadataSet(id, "version", "version", abi.encode("1.0"));
        registry.setMetadata(id, "version", abi.encode("1.0"));
    }

    // --- agent wallet ---

    function test_setAgentWallet_withEOASignature() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _computeDigest(id, wallet1, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet1, deadline, sig);

        assertEq(registry.getAgentWallet(id), wallet1);
    }

    function test_setAgentWallet_emitsEvent() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _computeDigest(id, wallet1, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user1);
        vm.expectEmit(true, true, false, false);
        emit IAgentIdentityRegistry.AgentWalletSet(id, wallet1);
        registry.setAgentWallet(id, wallet1, deadline, sig);
    }

    function test_setAgentWallet_revertsWithExpiredDeadline() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 deadline = block.timestamp - 1;
        bytes memory sig = hex"";

        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.SignatureExpired.selector);
        registry.setAgentWallet(id, wallet1, deadline, sig);
    }

    function test_setAgentWallet_revertsWithInvalidSignature() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 deadline = block.timestamp + 1 hours;
        bytes
            memory sig = hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.InvalidSignature.selector);
        registry.setAgentWallet(id, wallet1, deadline, sig);
    }

    function test_setAgentWallet_revertsForNonOwner() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user2);
        vm.expectRevert(IAgentIdentityRegistry.NotAgentOwner.selector);
        registry.setAgentWallet(id, wallet1, block.timestamp + 1 hours, hex"");
    }

    function test_setAgentWallet_revertsForAlreadySetSameWallet() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _computeDigest(id, wallet1, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet1, deadline, sig);

        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.WalletAlreadySet.selector);
        registry.setAgentWallet(id, wallet1, deadline, sig);
    }

    function test_setAgentWallet_incrementsNonce() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce1 = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest1 = _computeDigest(id, wallet1, nonce1, deadline);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest1);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet1, deadline, abi.encodePacked(r1, s1, v1));

        uint256 nonce2 = 1;
        bytes32 digest2 = _computeDigest(id, wallet2, nonce2, deadline);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(uint256(keccak256(abi.encodePacked("wallet2"))), digest2);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet2, deadline, abi.encodePacked(r2, s2, v2));

        assertEq(registry.getAgentWallet(id), wallet2);
    }

    function test_unsetAgentWallet_clearsWallet() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _computeDigest(id, wallet1, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet1, deadline, abi.encodePacked(r, s, v));
        assertEq(registry.getAgentWallet(id), wallet1);

        vm.prank(user1);
        registry.unsetAgentWallet(id);
        assertEq(registry.getAgentWallet(id), address(0));
    }

    function test_unsetAgentWallet_revertsWhenNotSet() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user1);
        vm.expectRevert(IAgentIdentityRegistry.WalletNotSet.selector);
        registry.unsetAgentWallet(id);
    }

    function test_unsetAgentWallet_revertsForNonOwner() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        vm.prank(user2);
        vm.expectRevert(IAgentIdentityRegistry.NotAgentOwner.selector);
        registry.unsetAgentWallet(id);
    }

    function test_transfer_clearsAgentWallet() public {
        vm.prank(user1);
        uint256 id = registry.register("ipfs://agent");

        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _computeDigest(id, wallet1, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(keccak256(abi.encodePacked("wallet1"))), digest);

        vm.prank(user1);
        registry.setAgentWallet(id, wallet1, deadline, abi.encodePacked(r, s, v));
        assertEq(registry.getAgentWallet(id), wallet1);

        vm.prank(user1);
        registry.transferFrom(user1, user2, id);

        assertEq(registry.getAgentWallet(id), address(0));
    }

    // --- view errors ---

    function test_getAgentWallet_revertsForNonExistent() public {
        vm.expectRevert(IAgentIdentityRegistry.AgentNotFound.selector);
        registry.getAgentWallet(99);
    }

    function test_getMetadata_revertsForNonExistent() public {
        vm.expectRevert(IAgentIdentityRegistry.AgentNotFound.selector);
        registry.getMetadata(99, "key");
    }

    function test_ownerOf_revertsForNonExistent() public {
        vm.expectRevert();
        registry.ownerOf(99);
    }
}
