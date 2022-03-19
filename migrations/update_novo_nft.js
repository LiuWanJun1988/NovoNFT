const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const NovoNFT = artifacts.require('NovoNFT');

module.exports = async function(deployer) {
    const instance = await upgradeProxy("0xEC79F308585FDc8b27A9Bb77B1F586d82c2a887b", NovoNFT, { deployer });
    console.log("Upgraded", instance.address);
};