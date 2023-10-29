// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

contract TestUtils is Test {
    function _nameToAddr(string memory name) internal pure returns (address) {
        return vm.addr(_nameToKey(name));
    }

    function _nameToKey(string memory name) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(name)));
    }
}
