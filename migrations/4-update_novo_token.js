const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const NOVOV2 = artifacts.require('NOVOV2');

module.exports = async function(deployer) {
    const instance = await upgradeProxy("0x25DCfa762Ae0fD3dE794F6E01Fdd2F98bbC33a85", NOVOV2, { deployer });
    console.log("Upgraded", instance.address);
};