// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PriceOracleInfo {
    string appToken;
    address linkToken;
    address chainlinkNode;
    string jobId;
    uint256 nodeFee; // should be the value multiplied by 1000 (0.1 = 100)
}

struct ScopeTimestamps {
    uint64 firstGSlabOpeningDate;
    uint64 lastGSlabEndingDate;
    uint64 maturityDate;
}
