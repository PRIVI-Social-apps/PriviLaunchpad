const { constants, time } = require('@openzeppelin/test-helpers');

function getData(dataType, accounts) {
  switch (dataType) {
    case 'tokenFundingData': {
      // All the timestamp values are set calling the updateTimesOf function

      let fundingScopeRoundsData = [
        {
          openingTime: 0,
          durationTime: 20,
          discount: 50,
          capTokensToBeSold: 1000,
          mintedTokens: 0,
        },
        {
          openingTime: 0,
          durationTime: 20,
          discount: 30,
          capTokensToBeSold: 1000,
          mintedTokens: 0,
        },
      ];

      let fundingStakeRoundsData = [
        {
          openingTime: 0,
          durationTime: 20,
          stakeReward: 50,
          capTokensToBeStaked: 1000,
          stakedTokens: 0,
        },
        {
          openingTime: 0,
          durationTime: 20,
          stakeReward: 40,
          capTokensToBeStaked: 1000,
          stakedTokens: 0,
        },
      ];

      let tokenFundingData = {
        appToken: constants.ZERO_ADDRESS,
        rMin: 5000,
        rMax: 15000,
        maturity: 0,
        t: 0,
        owners: [accounts[0], accounts[1], accounts[2]],
        fundingScopeRoundsData,
        fundingStakeRoundsData,
      };

      updateTimesOf(tokenFundingData);
      return tokenFundingData;
    }
    case 'priceOracleInfo': {
      let priceOracleInfo = {
        appToken: constants.ZERO_ADDRESS,
        linkToken: constants.ZERO_ADDRESS,
        chainlinkNode: constants.ZERO_ADDRESS,
        jobId: 'unset',
        nodeFee: 1,
      };

      return priceOracleInfo;
    }
  }
}

async function updateTimesOf(tokenFundingData) {
  let now = (await time.latest()).toNumber();
  let _15daysFromNow = now + time.duration.days(15).toNumber();

  tokenFundingData.maturity = _15daysFromNow;
  tokenFundingData.t = _15daysFromNow;

  tokenFundingData.fundingScopeRoundsData.forEach((round, index) => {
    round.openingTime = now + index * 20;
  });
  tokenFundingData.fundingStakeRoundsData.forEach((round, index) => {
    round.openingTime = now + index * 20;
  });
}

module.exports = { getData, updateTimesOf };
