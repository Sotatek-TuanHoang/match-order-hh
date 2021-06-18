require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
// task("accounts", "Prints the list of accounts", async () => {
//   const accounts = await ethers.getSigners();

//   for (const account of accounts) {
//     console.log(account.address);
//   }
// });



const DEPLOYER_PRIVATE_KEY = '0xf5c402199bc8be64eccc697f911beadf321049f8cb466ed8e1a282ba69654592';
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

