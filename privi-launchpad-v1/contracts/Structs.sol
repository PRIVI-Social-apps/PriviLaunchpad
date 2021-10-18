// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct App {
    address fundingTokenAddress;
    address appTokenAddress;
    address syntheticTokenAddress;
    address rangeTokenAddress;
}

struct AppFundingData {
    address fundingToken;
    uint256 s;
    uint256 rMin;
    uint256 rMax;
    uint256 x;
    uint256 y;
    uint256 t;
    uint256 maturity;
    address[] owners;
    FundingRoundsData[] fundingRangeRoundsData;
    FundingRoundsData[] fundingSyntheticRoundsData;
}

struct FundingRoundsData {
    uint64 openingTime;
    uint64 durationTime;
    uint128 tokenPrice;
    uint256 capTokenToBeSold;
    uint256 mintedTokens;
}

struct WithdrawProposal {
    uint128 positiveVotesCount;
    uint128 negativeVotesCount;
    address recipient;
    uint64 minApprovals;
    uint64 maxDenials;
    uint64 date;
    uint64 duration;
    uint256 amount;
    uint256 appId;
    bool fromRangeTokenContract;
}
