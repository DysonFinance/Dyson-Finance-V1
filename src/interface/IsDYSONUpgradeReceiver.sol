pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IsDYSONUpgradeReceiver {
    function onMigrationReceived(address, uint, uint, uint) external returns (bytes4);
}