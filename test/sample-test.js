const { expect } = require("chai");


describe("MatchOrderFullFillTwoSide", function() {
  it("Should return the new greeting once it's changed", async function() {
    const MatchOrdersFeature = await ethers.getContractFactory("MatchOrdersFeature");
    const matchOrdersFeature = await MatchOrdersFeature.deploy("0xd8a9465307a1bb5a2b7a4ed511ffae175b7d9bac");
    
    const leftOrder =  {
      makerToken: '0x849766c564ed666e198ea5ae42a4223b95faf64a',
      takerToken: '0x0e4355d3cB1796Bcf695c3172c43a151FBFDE367',
      makerAmount: '1000000000000000000',
      takerAmount: '1000000000000000000',
      maker: '0xF54b3294616d39749732Ac74F234F46C9ABf29C4',
      taker: '0x0000000000000000000000000000000000000000',
      pool: '0x5c6958f67b2c4c79cd9c7ec5f809cfc66da662039e3b82e6b98ef21428a0afd2',
      expiry: 1666586343,
      salt: '60201431490906934949084609448663233193267165660311320672636667079700383387797',
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
      pool: '0x8ecefe8b3e62acb95f755278951f7996a94fc00677115d6b7491090811dd3c15',
      expiry: 1666586343,
      salt: '72202544363047600315244214924352021656016615075980946171182803111939818896705',
      chainId: 15,
      verifyingContract: '0xd8a9465307a1bb5a2b7a4ed511ffae175b7d9bac',
      takerTokenFeeAmount: 0,
      sender: '0x0000000000000000000000000000000000000000',
      feeRecipient: '0x0000000000000000000000000000000000000000'
    }

    const leftSignature = {
      v: 28,
      r: '0x3d9ea168d97a6d58dc7d1db3e621b81b2e70c6b8573ddb761dc8ae8d6ed3befb',
      s: '0x26093170b26917c1dd43393eae637329079e2e6f987bd592eb96646d5a2bb7d7',
      signatureType: 2
    }

    const rightSignature = {
      v: 27,
      r: '0x5354ad68dbe8fe8f5d23fa2be26458fbdf377fb5726d96c4b34bd42dfc13f7bb',
      s: '0x516690c844feee7c46d761643e13c5739af7a6a8a4af79cccc6581d1b45fa56d',
      signatureType: 2
    }
    console.log(await matchOrdersFeature.matchOrders(leftOrder, rightOrder, leftSignature, rightSignature));
  });
});
