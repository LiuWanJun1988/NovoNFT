const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const NOVOV2 = artifacts.require('NOVOV2');

module.exports = async function(deployer) {
    const instance = await upgradeProxy("0xCb10A6B203120C50Cce48e3E1131aA717A82fb5F", NOVOV2, { deployer });
    console.log("Upgraded", instance.address);
};