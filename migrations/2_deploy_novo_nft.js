const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVO = artifacts.require('NOVO');
const NovoNFT = artifacts.require('NovoNFT');

module.exports = async function(deployer) {
    const instance = await deployProxy(NovoNFT, [NOVO.address], { deployer });
    console.log('Deployed: ', instance.address);
};