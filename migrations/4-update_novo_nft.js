const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const NovoNFT = artifacts.require('NovoNFT');

module.exports = async function(deployer) {
    const instance = await upgradeProxy("0x7F7F2FD74A56C868E4C0739b90e15A8a557f47f3", NovoNFT, { deployer });
    console.log("Upgraded", instance.address);
};