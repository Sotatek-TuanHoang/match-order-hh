require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
// task("accounts", "Prints the list of accounts", async () => {
//   const accounts = await ethers.getSigners();

//   for (const account of accounts) {
//     console.log(account.address);
//   }
// });



const DEPLOYER_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  // networks: {
  //   hardhat: {
  //   },
  //   evry: {
  //     chainId: 15,
  //     url: 'http://127.0.0.1:22002',
  //     accounts: [DEPLOYER_PRIVATE_KEY],
  //     saveDeployments: true,
  //   }
  // },
  solidity: {
    compilers: [
      {
        version: "0.6.5"
      },
      {
        version: "0.5.9",
        settings: { } 
      }
    ]
  }
};

