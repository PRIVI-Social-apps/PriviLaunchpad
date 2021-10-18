const FundingTokenMock = artifacts.require('FundingTokenMock');

module.exports = async function (_deployer, network) {
  if (network == 'development') {
    await _deployer.deploy(FundingTokenMock);
  }
};
