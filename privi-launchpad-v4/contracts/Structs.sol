// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct TokenFunding {
    address appTokenAddress;
    address insuranceAddress;
    address stakeTokenAddress;
    address scopeTokenAddress;
}

struct TokenFundingData {
    address appToken;
    uint256 rMin;
    uint256 rMax;
    uint128 t; // unlock time for stake tokens (app tokens)
    uint128 maturity; // maturity time for scope tokens
    address[] owners;
    FundingScopeRoundsData[] fundingScopeRoundsData;
    FundingStakeRoundsData[] fundingStakeRoundsData;
}

struct FundingStakeRoundsData {
    uint64 openingTime;
    uint64 durationTime;
    uint128 stakeReward; // value between 0 and REWARD_PRECISION (1000)
    uint256 capTokensToBeStaked;
    uint256 stakedTokens;
}

struct FundingScopeRoundsData {
    uint64 openingTime;
    uint64 durationTime;
    uint128 discount; // value between 0 and DISCOUNT_PRECISION (1000)
    uint256 capTokensToBeSold;
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
    uint256 tokenFundingId;
}
