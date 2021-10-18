const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');
const TokenFundingManager = artifacts.require('TokenFundingManager');
const WithdrawManager = artifacts.require('WithdrawManager');

module.exports = async function (_deployer) {
  let scopeToken = await ScopeToken.deployed();
  let stakeToken = await StakeToken.deployed();
  let insurance = await Insurance.deployed();
  let oracle = await SPOracle.deployed();
  let withdrawManager = await WithdrawManager.deployed();

  await _deployer.deploy(
    TokenFundingManager,
    withdrawManager.address,
    scopeToken.address,
    stakeToken.address,
    insurance.address,
    oracle.address
  );

  let tokenFundingManger = await TokenFundingManager.deployed();
  await withdrawManager.initialize(tokenFundingManger.address);
};
