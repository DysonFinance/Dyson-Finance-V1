// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

contract Addresses is Script {
    string file;

    /// @dev Read from config file. Need to set read permission for the config file in foundry.toml
    /// Config file is a JSON file and value is accessed by `vm.parseJson(file, ".lv1Key.lv2Key")`
    /// For example, to access WETH address in Mainnet: `vm.parseJson(file, `.mainnet.WETH`)`
    /// @param addrId Identifier for the address, e.g., "WETH"
    function getAddress(string memory addrId) internal returns (address) {
        file = vm.readFile("deploy-config.json");

        string memory key;
        if (block.chainid == 1) {
            // Mainnet
            key = string.concat(".mainnet.", addrId);
        } else if (block.chainid == 1101) {
            // Polygon zkEVM
            key = string.concat(".polygonZKEVM.", addrId);
        } else if (block.chainid == 5) {
            // Goerli
            key = string.concat(".goerli.", addrId);
        } else if (block.chainid == 11155111) {
            // Sepolia
            key = string.concat(".sepolia.", addrId);
        } else {
            // Default to local testnet
            key = string.concat(".local.", addrId);
        }
        bytes memory data = vm.parseJson(file, key);
        address addr = abi.decode(data, (address));
        return addr;
    }

    function setAddress(address addr, string memory addrId) internal {
        string memory path = "deploy-config.json";

        string memory key;
        if (block.chainid == 1) {
            // Mainnet
            key = string.concat(".mainnet.", addrId);
        } else if (block.chainid == 1101) {
            // Polygon zkEVM
            key = string.concat(".polygonZKEVM.", addrId);
        } else if (block.chainid == 5) {
            // Goerli
            key = string.concat(".goerli.", addrId);
        } else if (block.chainid == 11155111) {
            // Sepolia
            key = string.concat(".sepolia.", addrId);
        } else {
            // Default to local testnet
            key = string.concat(".local.", addrId);
        }
        
        string memory addrStr = toHexString(addr);
        vm.writeJson(addrStr, path, key);
    }

    function getRelyNeededAddresses(string memory addressType) internal returns (address[] memory addresses) {
        addresses = vm.parseJsonAddressArray(file, addressType);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        bytes16 HEX_DIGITS = "0123456789abcdef";
        uint256 value = uint256(uint160(addr));
        uint length = 20;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}