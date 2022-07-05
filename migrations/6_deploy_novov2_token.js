const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const NOVOV2 = artifacts.require('NOVOV2');
// ETH Univ2 router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
// BSC:  0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 (Testnet) | 0x10ed43c718714eb63d5aa57b78b54704e256024e (Mainnet)
module.exports = async function(deployer) {
    const instance = await deployProxy(NOVOV2, ["0x10ed43c718714eb63d5aa57b78b54704e256024e"], { deployer });
    console.log('Deployed: ', instance.address);
};