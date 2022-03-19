require('dotenv').config();

const HDWalletProvider = require('@truffle/hdwallet-provider'); // @notice - Should use new module.
const mnemonic = process.env.MNEMONIC;

module.exports = {
    networks: {
        bsc_testnet: { /// This is used for deployment and truffle test
            provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s2.binance.org:8545`), /// [Note]: New RPC Endpoint
            network_id: 97,
            networkCheckTimeout: 9999,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true
        },
        bsc_mainnet: { /// Binance Smart Chain mainnet
            provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
            network_id: 56,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true
        },
        rinkeby: {
            provider: () => new HDWalletProvider(mnemonic, "wss://rinkeby.infura.io/ws/v3/" + process.env.INFURA_KEY),
            network_id: 4, // Rinkeby's id
            gas: 7500000,
            // gasPrice: 100, // 1 gwei (in wei) (default: 100 gwei)
            // networkCheckTimeout: 1000000,
            confirmations: 1, // # of confs to wait between deployments. (default: 0)
            timeoutBlocks: 200, // # of blocks before a deployment times out  (minimum/default: 50)
            skipDryRun: true,
            websocket: true // Skip dry run before migrations? (default: false for public nets )
        },
        ropsten: {
            provider: () => new HDWalletProvider(mnemonic, 'https://ropsten.infura.io/v3/' + process.env.INFURA_KEY),
            network_id: '3',
            gas: 4712388,
            //gas: 4465030,          // Original
            //gasPrice: 5000000000,  // 5 gwei (Original)
            //gasPrice: 10000000000, // 10 gwei
            gasPrice: 100000000000, // 100 gwei
            skipDryRun: true, // Skip dry run before migrations? (default: false for public nets)
        },
        local: {
            host: '127.0.0.1',
            port: 7545,
            network_id: '*',
            skipDryRun: true,
            gasPrice: 5000000000
        }
    },

    compilers: {
        solc: {
            version: "0.8.12", /// Final version of solidity-v0.6.x
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                }
            }
        }
    },
    plugins: ['truffle-plugin-verify'],
    api_keys: {
        // etherscan: process.env.ETHERSCAN_API,
        bscscan: process.env.BSCSCAN_API
    }
}