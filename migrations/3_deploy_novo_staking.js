const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVO = artifacts.require('NOVO');
const NovoStaking = artifacts.require('NovoStaking');

module.exports = async function(deployer) {
    const instance = await deployProxy(NovoStaking, [NOVO.address], { deployer });
    console.log('Deployed: ', instance.address);
};