const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVOV2 = artifacts.require('NOVOV2');
// ETH Univ2 router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
// BSC:  0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
module.exports = async function(deployer) {
    const instance = await deployProxy(NOVOV2, ["0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3", "0x7F7F2FD74A56C868E4C0739b90e15A8a557f47f3"], { deployer });
    console.log('Deployed: ', instance.address);
};