async function main() {
    const Factory = await ethers.getContractFactory("BackerFactory");
    
    // Start deployment, returning a promise that resolves to a contract object
    const contract = await Factory.deploy();
    console.log("Factory deployed to address:", contract.address);
 }
 
 main()
   .then(() => process.exit(0))
   .catch(error => {
     console.error(error);
     process.exit(1);
   });

// npx hardhat run scripts/deploy.js --network localhost
// npx hardhat verify --network rinkeby DEPLOYED_CONTRACT_ADDRESS
// npx hardhat node --fork https://eth-kovan.alchemyapi.io/v2/n_mDCfTpJ8I959arPP7PwiOptjubLm57 --fork-block-number 28424594