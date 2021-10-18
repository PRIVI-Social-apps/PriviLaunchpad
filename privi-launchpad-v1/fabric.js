const { constants, time } = require('@openzeppelin/test-helpers');

function getData(dataType, accounts) {
  switch (dataType) {
    case 'appData': {
      let fundingRangeRoundsData = [
        {
          openingTime: 0,
          durationTime: 20,
          tokenPrice: 5000,
          capTokenToBeSold: 1000,
          mintedTokens: 0,
        },
        {
          openingTime: 0,
          durationTime: 20,
          tokenPrice: 10000,
          capTokenToBeSold: 1000,
          mintedTokens: 0,
        },
      ];

      let fundingSyntheticRoundsData = [
        {
          openingTime: 0,
          durationTime: 20,
          tokenPrice: 8000,
          capTokenToBeSold: 1000,
          mintedTokens: 0,
        },
        {
          openingTime: 0,
          durationTime: 20,
          tokenPrice: 9000,
          capTokenToBeSold: 1000,
          mintedTokens: 0,
        },
      ];

      let appFundingData = {
        fundingToken: constants.ZERO_ADDRESS,
        s: 10000,
        rMin: 5000,
        rMax: 15000,
        x: 10,
        y: 10,
        maturity: 0,
        t: 0,
        owners: [accounts[0], accounts[1], accounts[2]],
        fundingRangeRoundsData,
        fundingSyntheticRoundsData,
      };

      updateTimesOf(appFundingData);
      return appFundingData;
    }
  }
}

async function updateTimesOf(appFundingData) {
  let now = (await time.latest()).toNumber();
  let _15daysFromNow = now + time.duration.days(15).toNumber();

  appFundingData.maturity = _15daysFromNow;
  appFundingData.t = _15daysFromNow;

  appFundingData.fundingRangeRoundsData.forEach((round, index) => {
    round.openingTime = now + index * 20;
  });
  appFundingData.fundingSyntheticRoundsData.forEach((round, index) => {
    round.openingTime = now + index * 20;
  });
}

module.exports = { getData, updateTimesOf };
