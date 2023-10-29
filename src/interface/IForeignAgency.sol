
pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IForeignAgency {
    function adminAddForeign(address newUser, uint gen, uint slotUsed) external returns (uint id);
}