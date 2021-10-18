const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');

module.exports = function (deployer) {
  deployer.deploy(RangeToken);
  deployer.deploy(SyntheticToken);
  deployer.deploy(AppToken);
};
