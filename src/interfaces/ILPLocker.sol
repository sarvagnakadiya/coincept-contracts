// ILPLocker.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILPLocker {
    function collectRewards(
        uint256 tokenId
    ) external returns (uint256 amount0, uint256 amount1);
}
