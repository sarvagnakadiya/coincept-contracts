// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClankerVault {
    function editAllocationAdmin(address token, address newAdmin) external;
}
