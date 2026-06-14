// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {ebool, euint8, euint16, euint32, euint64, euint128, eaddress} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {InEbool, InEuint8, InEuint16, InEuint32, InEuint64, InEuint128, InEaddress, EncryptedInput, Utils} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

address constant TASK_MANAGER_ADDRESS = 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9;

interface ITaskManagerMeta {
    function verifyInput(EncryptedInput memory input, address sender) external returns (uint256);
}

library FHEMeta {
    error InvalidEncryptedInput(uint8 got, uint8 expected);

    function asEbool(InEbool memory value, address sender) internal returns (ebool) {
        uint8 expectedUtype = Utils.EBOOL_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            ebool.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEbool(value), sender))
            );
    }

    function asEuint8(InEuint8 memory value, address sender) internal returns (euint8) {
        uint8 expectedUtype = Utils.EUINT8_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            euint8.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEuint8(value), sender))
            );
    }

    function asEuint16(InEuint16 memory value, address sender) internal returns (euint16) {
        uint8 expectedUtype = Utils.EUINT16_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            euint16.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEuint16(value), sender))
            );
    }

    function asEuint32(InEuint32 memory value, address sender) internal returns (euint32) {
        uint8 expectedUtype = Utils.EUINT32_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            euint32.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEuint32(value), sender))
            );
    }

    function asEuint64(InEuint64 memory value, address sender) internal returns (euint64) {
        uint8 expectedUtype = Utils.EUINT64_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            euint64.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEuint64(value), sender))
            );
    }

    function asEuint128(InEuint128 memory value, address sender) internal returns (euint128) {
        uint8 expectedUtype = Utils.EUINT128_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            euint128.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEuint128(value), sender))
            );
    }

    function asEaddress(InEaddress memory value, address sender) internal returns (eaddress) {
        uint8 expectedUtype = Utils.EADDRESS_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }
        return
            eaddress.wrap(
                bytes32(ITaskManagerMeta(TASK_MANAGER_ADDRESS).verifyInput(Utils.inputFromEaddress(value), sender))
            );
    }
}
