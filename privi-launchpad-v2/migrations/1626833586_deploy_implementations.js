const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');

module.exports = function (deployer) {
  deployer.deploy(ScopeToken);
  deployer.deploy(StakeToken);
  deployer.deploy(Insurance);
  deployer.deploy(SPOracle);
};
