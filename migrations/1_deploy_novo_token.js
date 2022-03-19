const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVO = artifacts.require('NOVO');
// ETH Univ2 router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
// BSC:  0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
module.exports = async function(deployer) {
    const instance = await deployProxy(NOVO, ["0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"], { deployer });
    console.log('Deployed: ', instance.address);
};