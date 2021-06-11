const { expect } = require("chai");

describe("Greeter", function() {
  it("Should return the new greeting once it's changed", async function() {
    const Greeter = await ethers.getContractFactory("MatchOrdersFeature");
    const greeter = await Greeter.deploy("0xd8a9465307a1bb5a2b7a4ed511ffae175b7d9bac");
    
    const leftOrder ={
      makerToken: '0x849766c564ed666e198ea5ae42a4223b95faf64a',
      takerToken: '0x0e4355d3cB1796Bcf695c3172c43a151FBFDE367',
      makerAmount: '1000000000000000000',
      takerAmount: '1000000000000000000',
      maker: '0xF54b3294616d39749732Ac74F234F46C9ABf29C4',
      taker: '0x0000000000000000000000000000000000000000',
      pool: '0x08e03105d5316a63f7ad76055fd1c914f92e5df176eee9f4d1d2f73f230619e6',
      expiry: 1623422549,
      salt: '58029194395013538598904475410689725043387451188159321018321111529221029444680',
      chainId: 15,
      verifyingContract: '0xd8a9465307a1bb5a2b7a4ed511ffae175b7d9bac',
      takerTokenFeeAmount: 0,
      sender: '0x0000000000000000000000000000000000000000',
      feeRecipient: '0x0000000000000000000000000000000000000000'
    }
  
  
    const rightOrder = {
      makerToken: '0x0e4355d3cB1796Bcf695c3172c43a151FBFDE367',
      takerToken: '0x849766c564ed666e198ea5ae42a4223b95faf64a',
      makerAmount: '1000000000000000000',
      takerAmount: '1000000000000000000',
      maker: '0xBdD34ca459A9Ff4B673aC398F856c0A24F408963',
      taker: '0x0000000000000000000000000000000000000000',
      pool: '0x4e5235272ee47a7090a35324922616bd7e20baac3cc137b14c3c6ff7c467d233',
      expiry: 1623421773,
      salt: '27513909888570048402289410100575645630836285617519850957248424819823924198883',
      chainId: 15,
      verifyingContract: '0xd8a9465307a1bb5a2b7a4ed511ffae175b7d9bac',
      takerTokenFeeAmount: 0,
      sender: '0x0000000000000000000000000000000000000000',
      feeRecipient: '0x0000000000000000000000000000000000000000'
    }
  
  

    const leftSignature = {
      r: '0xb6196ce3604bcb92a089d5b3da8f55309c826a8d4c769fe0c12e29c9d8ee5f7d',
      s: '0x68005c5e06e7ffd22f88bffaaa8f5c1c44e380d5a6a407c10ecf3c7cc6b06111',
      v: 28,
      signatureType: 2
    }

    const rightSignature = {
      v: 27,
      r: '0x4d30cafe48b16b8166199f6e60ae21b78e3b1d985a6a46f2e8d2ba1e28a9d2a3',
      s: '0x113942ac8d66c966c6c527bc5b314e28f913c78a2b71c3fd8540591d9390a4a6',
      signatureType: 2
    }
    console.log("deploy done");


    console.log(await greeter.matchOrders(leftOrder, rightOrder, leftSignature, rightSignature));
  });
});
