const WithdrawManager = artifacts.require('WithdrawManager');

module.exports = function (deployer) {
  deployer.deploy(WithdrawManager);
};
