const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NovoNFT = artifacts.require('NovoNFT');

module.exports = async function(deployer) {
    const instance = await deployProxy(NovoNFT, [], { deployer });
    console.log('Deployed: ', instance.address);
};