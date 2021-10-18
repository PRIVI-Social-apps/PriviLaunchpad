const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const AppFundingManager = artifacts.require('AppFundingManager');
const WithdrawManager = artifacts.require('WithdrawManager');

module.exports = async function (_deployer) {
  let rangeToken = await RangeToken.deployed();
  let syntheticToken = await SyntheticToken.deployed();
  let appToken = await AppToken.deployed();
  let withdrawManager = await WithdrawManager.deployed();

  await _deployer.deploy(
    AppFundingManager,
    withdrawManager.address,
    rangeToken.address,
    syntheticToken.address,
    appToken.address
  );

  let appFundingManger = await AppFundingManager.deployed();
  await withdrawManager.initialize(appFundingManger.address);
};
