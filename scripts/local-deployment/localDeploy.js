const path = require("path");
const pathDeployParameters = path.join(__dirname, "./deploy_parameters.json");
const deployParameters = require(pathDeployParameters);
const pathOutputJson = deployParameters.pathOutputJson || path.join(__dirname, "./deploy_output.json");

process.env.HARDHAT_NETWORK = deployParameters.hardhatNetwork;
const bre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

const fs = require("fs");
const poseidonUnit = require("circomlib/src/poseidon_gencontract");

const {
  calculateInputMaxTxLevels,
} = require("../../test/perp/helpers/helpers");


const maxTxVerifierDefault = [8, 400, 2048];
const nLevelsVeriferDefault = [32, 32, 32];
const verifierTypeDefault = ["real","real", "real"];

async function main() {
  // compìle contracts
  await bre.run("compile");

  // load Mnemonic accounts:
  const signersArray = await ethers.getSigners();

  // index 0 would use as the deployer address
  const [deployer] = signersArray;

  // get chain ID
  const chainId = (await ethers.provider.getNetwork()).chainId;

  console.log(
    `Deploying contracts with the account(${chainId}):`,
    await deployer.getAddress()
  );

  console.log("Account balance:", (await deployer.getBalance()).toString());

  // get contract factorys
  let Perpetual = await ethers.getContractFactory("Perpetual");

  // perp libs

  const VerifierRollupMock = await ethers.getContractFactory(
    "VerifierRollupHelper"
  );

  const Poseidon2Elements = new ethers.ContractFactory(
    poseidonUnit.generateABI(2),
    poseidonUnit.createCode(2),
    deployer
  );

  const Poseidon3Elements = new ethers.ContractFactory(
    poseidonUnit.generateABI(3),
    poseidonUnit.createCode(3),
    deployer
  );

  const Poseidon4Elements = new ethers.ContractFactory(
    poseidonUnit.generateABI(4),
    poseidonUnit.createCode(4),
    deployer
  );

  const Poseidon5Elements = new ethers.ContractFactory(
      poseidonUnit.generateABI(5),
      poseidonUnit.createCode(5),
      deployer
  );

  let maxTxVerifier = deployParameters[chainId].maxTxVerifier || maxTxVerifierDefault;
  let nLevelsVerifer = deployParameters[chainId].nLevelsVerifer || nLevelsVeriferDefault;
  // console.log(calculateInputMaxTxLevels(maxTxVerifier, nLevelsVerifer))


  // Deploy smart contacts:

  // deploy smart contracts with proxy https://github.com/OpenZeppelin/openzeppelin-upgrades/blob/master/packages/plugin-hardhat/test/initializers.js
  // or intializer undefined and call initialize later

  // Deploy perp
  const perp = await upgrades.deployProxy(Perpetual, [], {
    unsafeAllowCustomTypes: true,
    initializer: undefined,
  });
  await perp.deployed();

  console.log("perp deployed at: ", perp.address);

  // load or deploy libs

  // poseidon libs
  let libposeidonsAddress = deployParameters[chainId].libPoseidonsAddress;
  if (!libposeidonsAddress || libposeidonsAddress.length != 4) {
    const hardhatPoseidon2Elements = await Poseidon2Elements.deploy();
    const hardhatPoseidon3Elements = await Poseidon3Elements.deploy();
    const hardhatPoseidon4Elements = await Poseidon4Elements.deploy();
    const hardhatPoseidon5Elements = await Poseidon5Elements.deploy();
    await hardhatPoseidon2Elements.deployed();
    await hardhatPoseidon3Elements.deployed();
    await hardhatPoseidon4Elements.deployed();
    await hardhatPoseidon5Elements.deployed();

    libposeidonsAddress = [
      hardhatPoseidon2Elements.address,
      hardhatPoseidon3Elements.address,
      hardhatPoseidon4Elements.address,
      hardhatPoseidon5Elements.address,
    ];
    console.log("deployed poseidon libs");
    console.log("poseidon 2 elements at: ", hardhatPoseidon2Elements.address);
    console.log("poseidon 3 elements at: ", hardhatPoseidon3Elements.address);
    console.log("poseidon 4 elements at: ", hardhatPoseidon4Elements.address);
    console.log("poseidon 5 elements at: ", hardhatPoseidon5Elements.address);
  } else {
    console.log("posidon libs already depoloyed");
  }

  // maxTx and nLevelsVerifer must have the same number of elements as verifiers

  let verifierType = deployParameters[chainId].verifierType || verifierTypeDefault;

  // verifiers rollup libs
  let libVerifiersAddress = deployParameters[chainId].libVerifiersAddress;

  if (!libVerifiersAddress || libVerifiersAddress.length == 0) {
    libVerifiersAddress = [];
    console.log("deployed verifiers libs");
    for (let i = 0; i < maxTxVerifier.length; i++) {
      if (verifierType[i] == "real") {
        const VerifierRollupReal = await ethers.getContractFactory(
          `Verifier${maxTxVerifier[i]}`
        );
        const hardhatVerifierRollupReal = await VerifierRollupReal.deploy();
        await hardhatVerifierRollupReal.deployed();
        libVerifiersAddress.push(hardhatVerifierRollupReal.address);
        console.log("verifiers Real deployed at: ", hardhatVerifierRollupReal.address);
      }
      else {
        const hardhatVerifierRollupMock = await VerifierRollupMock.deploy();
        await hardhatVerifierRollupMock.deployed();
        libVerifiersAddress.push(hardhatVerifierRollupMock.address);
        console.log("verifiers Mock deployed at: ", hardhatVerifierRollupMock.address);
      }
    }
  } else {
    console.log("verifier libs already depoloyed");
  }

  // initialize upgradable smart contracts

  // initialize Perpetual

  await perp.init(
      await deployer.getAddress(),
      deployParameters[chainId].depositTokenAddress,
    libVerifiersAddress,
    calculateInputMaxTxLevels(maxTxVerifier, nLevelsVerifer),
    libposeidonsAddress,
  );

  await perp.setOperator(await deployer.getAddress())
  await perp.setInsAccId(13084334)
  await perp.setFeeAccId(13084326)

  console.log("perp Initialized");

  // in case the mnemonic accounts are used, return the index, otherwise, return null
  const outputJson = {
    perpAddress: perp.address,
    hardhatNetwork: deployParameters.hardhatNetwork,
    mnemonic: deployParameters.mnemonic,
    test: deployParameters.test
  };

  fs.writeFileSync(pathOutputJson, JSON.stringify(outputJson, null, 1));
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
