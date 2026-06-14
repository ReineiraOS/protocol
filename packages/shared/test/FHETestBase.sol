// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {CofheTest} from "@cofhe/foundry-plugin/contracts/CofheTest.sol";
import {CofheClient} from "@cofhe/foundry-plugin/contracts/CofheClient.sol";
import {InEbool, InEuint8, InEuint16, InEuint32, InEuint64, InEuint128, InEaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

abstract contract FHETestBase is CofheTest {
    mapping(address => uint256) internal _pkeys;
    mapping(address => CofheClient) internal _clients;

    function _initFHE() internal {
        deployMocks();
    }

    function _makeAccount(string memory label) internal returns (address a) {
        uint256 p;
        (a, p) = makeAddrAndKey(label);
        _pkeys[a] = p;
    }

    function _registerAccount(address a, uint256 p) internal {
        _pkeys[a] = p;
    }

    function _client(address account) internal returns (CofheClient c) {
        c = _clients[account];
        if (address(c) == address(0)) {
            uint256 pkey = _pkeys[account];
            require(pkey != 0, "FHETestBase: account has no pkey; use _makeAccount or _registerAccount");
            c = createCofheClient();
            c.connect(pkey);
            _clients[account] = c;
        }
    }

    function createInEbool(bool v, address account) internal returns (InEbool memory) {
        return _client(account).createInEbool(v);
    }

    function createInEuint8(uint8 v, address account) internal returns (InEuint8 memory) {
        return _client(account).createInEuint8(v);
    }

    function createInEuint16(uint16 v, address account) internal returns (InEuint16 memory) {
        return _client(account).createInEuint16(v);
    }

    function createInEuint32(uint32 v, address account) internal returns (InEuint32 memory) {
        return _client(account).createInEuint32(v);
    }

    function createInEuint64(uint64 v, address account) internal returns (InEuint64 memory) {
        return _client(account).createInEuint64(v);
    }

    function createInEuint128(uint128 v, address account) internal returns (InEuint128 memory) {
        return _client(account).createInEuint128(v);
    }

    function createInEaddress(address v, address account) internal returns (InEaddress memory) {
        return _client(account).createInEaddress(v);
    }
}
