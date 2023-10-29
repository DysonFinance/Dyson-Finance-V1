pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface ITreasuryVester {
    function token() external view returns (address);
    function recipient() external view returns (address);
    function vestingAmount() external view returns (uint);
    function vestingBegin() external view returns (uint);
    function vestingCliff() external view returns (uint);
    function vestingEnd() external view returns (uint);
    function lastUpdate() external view returns (uint);
    function setRecipient(address recipient_) external;
    function claim() external;
}
