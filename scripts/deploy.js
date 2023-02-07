import { ethers } from "ethers";
import { readFileSync, write, writeFileSync } from "fs";
import solc from "solc";
import { parse } from "toml";

const Foundry = parse(readFileSync("foundry.toml")).profile.default;

/**
 * @typedef {{ content: string }}
 */
const SourceFile = {};

/** @const {string} */
const DOMAIN_SEPARATOR = "0x7fac9a4ba27a28c432ccad9cad6a299334875c9ce9801df0d292862b0d4f51cb";

/**
 * @typedef {string}
 */
const ChainID = {};

/** @type {!Object<ChainID, !Array<string>>} */
const ChainData = {
  "0xa869": ["api.avax-test.network/ext/bc/C/rpc", "avalanche", "AVAX"],
  "0x1": ["cloudflare-eth.com", "ethereum", "ETH"],
  "0xa86a": ["api.avax.network/ext/bc/C/rpc", "avalanche", "AVAX"],
  "0x89": ["polygon-rpc.com", "polygon", "MATIC"],
  "0xa4b1": ["arb1.arbitrum.io/rpc", "ethereum", "ETH"],
  "0x38": ["bsc-dataseed3.binance.org", "binance-coin", "BNB"],
  "0x406": ["evm.confluxrpc.com", "conflux-network", "CFX"],
  "0xfa": ["rpc.ankr.com/fantom", "fantom", "FTM"],
}

/**
 * @param {ChainID}
 * @return {!Promise<number>}
 */
const getPrice = (chainId) => fetch(`https://api.coincap.io/v2/assets/${ChainData[chainId][1]}`)
  .then((res) => res.json())
  .then((data) => data["data"]["priceUsd"]);

/**
 * @param {!Array<string>} sourceNames
 * @param {string} chainId
 * @return {!Object<string, !SourceFile>}
 */
const readSources = (sourceNames) => Object.fromEntries(
  sourceNames.map((name) => [name, {
    content: readFileSync(name.startsWith("interfaces")
      ? "lib/interfaces/contracts" + name.slice(10)
      : "contracts/" + name, "utf-8"
    )
  }])
)

/**
 * @param {ChainID} chainId
 * @param {string} deployerAddress
 */
const computeDomainSeparator = (chainId, deployerAddress) =>
  ethers.TypedDataEncoder.hashDomain({
    name: 'TCKT',
    version: '1',
    chainId,
    verifyingContract: ethers.getCreateAddress({
      from: deployerAddress,
      nonce: 0
    })
  });

/**
 * @param {!Object<string, !SourceFile>} sources
 * @param {string} chainId
 * @param {string} deployerAddress
 * @return {!Object<string, !SourceFile>}
 */
const processSources = (sources, chainId, deployerAddress) => {
  const domainSeparator = computeDomainSeparator(chainId, deployerAddress);
  let file = sources["TCKT.sol"].content;

  if (!file.includes(DOMAIN_SEPARATOR)) {
    console.error("TCKT.sol does not have the right DOMAIN_SEPARATOR");
    process.exit(1);
  }
  file = file.replace(DOMAIN_SEPARATOR, domainSeparator);
  if (!chainId.startsWith("0xa86"))
    file = file.slice(0, file.indexOf("// Exposure report") - 92) + "}";
  sources["TCKT.sol"].content = file;
  return sources;
}

/**
 * @param {string} bytecode
 * @param {ChainID} chainId
 * @param {string} deployerAddress
 */
const compareAgainstFoundry = (bytecode, chainId, deployerAddress) => {
  /** @const {string} */
  const domainSeparator = computeDomainSeparator(chainId, deployerAddress);
  console.log(`   👉 Old:        ${DOMAIN_SEPARATOR}`);
  console.log(`   👉 New:        ${domainSeparator}`);

  const foundryBytecode = JSON.parse(readFileSync("out/TCKT.sol/TCKT.json"))
    .bytecode.object.slice(2)
    .replaceAll(DOMAIN_SEPARATOR.slice(2), domainSeparator.slice(2));
  console.log(`   📏 Size:       ${foundryBytecode.length / 2}`);
  const same = bytecode.slice(0, -86) == foundryBytecode.slice(0, -86);
  console.log(`   🤝 Compare:    ${same ? "👍" : "👎"}`);
  if (!same) process.exit(1);
}

/**
 * @param {ChainID} chainId
 * @param {string} privKey
 * @return {!Promise<void>}
 */
const deployToChain = async (chainId, privKey) => {
  /** @const {!ethers.Provider} */
  const provider = new ethers.JsonRpcProvider("https://" + ChainData[chainId][0]);
  /** @const {!ethers.Wallet} */
  const wallet = new ethers.Wallet(privKey, provider);
  /** @const {string} */
  const deployedAddress = ethers.getCreateAddress({
    from: wallet.address,
    nonce: 0
  });
  /** @const {number} */
  const nonce = await provider.getTransactionCount(wallet.address, "pending");

  console.log(`⛓️  Chain:         ${chainId}`);
  console.log(`📟 Deployer:      ${wallet.address}`);
  console.log(`📜 Contract:      ${deployedAddress}`);
  console.log(`🧮 Nonce:         ${nonce}, ${nonce == 0 ? "👍" : "👎"}`)

  console.log(`🌀 Compiling...   TCKT for ${chainId} and address ${deployedAddress}`);
  const compilerInput = JSON.stringify({
    language: "Solidity",
    sources: processSources(readSources([
      "interfaces/Addresses.sol",
      "interfaces/IDIDSigners.sol",
      "interfaces/IERC20.sol",
      "interfaces/IERC20Permit.sol",
      "interfaces/IERC721.sol",
      "TCKT.sol",
    ]), chainId, wallet.address),
    settings: {
      optimizer: {
        enabled: Foundry.optimizer,
        runs: Foundry.optimizer_runs,
      },
      outputSelection: {
        "TCKT.sol": {
          "TCKT": ["abi", "evm.bytecode.object"]
        }
      }
    },
  });
  console.log(`💾 Saving:        ${chainId}.verify.json`);
  writeFileSync(chainId + ".verify.json", compilerInput);

  /** @const {string} */
  const output = solc.compile(compilerInput);
  /** @const {!Object} */
  const solcJson = JSON.parse(output);
  const TCKT = solcJson.contracts["TCKT.sol"]["TCKT"];

  console.log(`📏 Binary size:   ${TCKT.evm.bytecode.object.length / 2} bytes`);
  if (chainId.startsWith("0xa86")) {
    console.log(`🔺 Avalanche:     Comparing against foundry compiled binary`);
    compareAgainstFoundry(TCKT.evm.bytecode.object, chainId, wallet.address);
  }

  const feeData = await provider.getFeeData();

  console.log(`🏭 Factory:       👍`);
  console.log(`⛽️ Gas price:     ${feeData.gasPrice / 1_000_000_000n}`);
  if (feeData.maxPriorityFeePerGas)
    console.log(`🫙  Max priority:  ${feeData.maxPriorityFeePerGas / 1_000_000_000n}`);

  const factory = new ethers.ContractFactory(TCKT.abi, TCKT.evm.bytecode.object, wallet);
  const deployTx = await factory.getDeployTransaction();

  /** @const {!bigint} */
  const estimatedGas = await provider.estimateGas(deployTx);
  console.log(`🙀 Gas estimate:  ${estimatedGas.toLocaleString('tr-TR')}`);
  const milliToken = Number(estimatedGas * feeData.gasPrice / 1_000_000_000_000_000n);
  const tokenPrice = await getPrice(chainId);
  const usdValue = ((tokenPrice * milliToken) | 0) / 1000;
  console.log(`💰 Estimated fee: ${milliToken / 1000} ${ChainData[chainId][2]} ` +
    `($${usdValue})        assuming 🪙  = $${tokenPrice}`);

  if (nonce != 0) return;
  const contract = await factory.deploy()
  console.log(`✨ Deployed:      ${contract.address}`);
  console.log(contract.deploymentTransaction);
}

deployToChain("0xa869", "0x32ad0ed30e1257b02fc85fa90a8179241cc38d926a2a440d8f6fbfd53b905c33");
