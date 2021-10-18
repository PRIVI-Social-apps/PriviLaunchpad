const AppTokenMock = artifacts.require('AppTokenMock');

module.exports = async function (_deployer, network) {
  if (network != 'matic' && network != 'live' && network != 'bsc') {
    await _deployer.deploy(AppTokenMock);
  }
};
