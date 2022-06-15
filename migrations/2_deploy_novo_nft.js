const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVOV2 = artifacts.require('NOVOV2');
const NovoNFT = artifacts.require('NovoNFT');

module.exports = async function(deployer) {
    const instance = await deployProxy(NovoNFT, [NOVOV2.address], { deployer });
    console.log('Deployed: ', instance.address);
};