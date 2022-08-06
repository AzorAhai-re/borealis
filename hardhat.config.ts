/**
 * @type import('hardhat/config').HardhatUserConfig
 */
import "@nomiclabs/hardhat-waffle";
import '@nomiclabs/hardhat-ethers';
import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import "hardhat-gas-trackooor";

export default {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {}
      },
    ],
  },
  networks: {
    hardhat: {
      gas: 10000000,
      gasPrice: 875000000,
    }
  }
};
