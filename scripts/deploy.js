import { ethers } from "ethers";
import { readFileSync } from "fs";
import solc from "solc";
import { parse } from "toml";

/**
 * @typedef {{ content: string }}
 */
let SourceFile;

/** @const {string} */
const DOMAIN_SEPARATOR = "0x7fac9a4ba27a28c432ccad9cad6a299334875c9ce9801df0d292862b0d4f51cb";

/** @type {!Object<string, !Array<string>>} */
const JsonRpcUrls = {
  "0x1": ["cloudflare-eth.com", "Ethereum"],
  "0xa86a": ["api.avax.network/ext/bc/C/rpc", "Avalanche"],
  "0x89": ["polygon-rpc.com", "Polygon"],
  "0xa4b1": ["arb1.arbitrum.io/rpc", "Arbitrum"],
  "0x38": ["bsc-dataseed3.binance.org", "BNB Chain"],
  "0x406": ["evm.confluxrpc.com", "Conflux eSpace"],
  "0xfa": ["rpc.ankr.com/fantom", "Fantom"],
}

/**
 * @param {Array<string>} sourceNames
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
 * @param {string} chainId
 * @param {string} deployerAddress
 */
const computeDomainSeparator = (chainId, deployerAddress) =>
  ethers.utils._TypedDataEncoder.hashDomain({
    name: 'TCKT',
    version: '1',
    chainId,
    verifyingContract: ethers.utils.getContractAddress({
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
  console.log(`${chainId}\tDOMAIN_SEPARATOR() = ${domainSeparator}`);

  if (!file.includes(DOMAIN_SEPARATOR)) {
    console.error("TCKT.sol does not have the right DOMAIN_SEPARATOR");
    process.exit(1);
  }
  file = file.replace(DOMAIN_SEPARATOR, domainSeparator);
  if (chainId != "0xa86a")
    file = file.slice(0, file.indexOf("// Exposure report") - 92) + "}";
  sources["TCKT.sol"].content = file;
  return sources;
}

/**
 * @param {string} bytecode
 * @param {string} chainId
 * @param {string} deployerAddress
 */
const compareAgainstFoundry = (bytecode, chainId, deployerAddress) => {
  if (chainId != "0xa86a") return;
  const domainSeparator = computeDomainSeparator(chainId, deployerAddress);
  const foundryBytecode = JSON.parse(readFileSync("out/TCKT.sol/TCKT.json"))
    .bytecode.object.slice(2)
    .replaceAll(DOMAIN_SEPARATOR.slice(2), domainSeparator.slice(2));
  console.log(domainSeparator);
  if (bytecode.slice(0, -86) != foundryBytecode.slice(0, -86)) {
    console.log("Bytecode differs from Foundry compiled one " + chainId);
    process.exit(1);
  }
}

/**
 * @param {string} chainId
 * @param {string} privKey
 * @return {Promise<void>}
 */
const deployToChain = (chainId, privKey) => {
  /** @const {!ethers.Provider} */
  const provider = new ethers.providers.JsonRpcProvider("https://" + JsonRpcUrls[chainId][0]);
  /** @const {!ethers.Wallet} */
  const wallet = new ethers.Wallet(privKey, provider);

  provider.getTransactionCount(wallet.address, "pending")
    .then((nonce) => {
      if (nonce) {
        console.warn(`${chainId}\tThere is a previous deployment with this private key on ${chainId}.`);
        return;
      }
      const compilerInput = {
        language: "Solidity",
        sources: processSources(readSources([
          "IDIDSigners.sol",
          "interfaces/Addresses.sol",
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
      }
      const output = JSON.parse(solc.compile(JSON.stringify(compilerInput)));
      const TCKT = output.contracts["TCKT.sol"]["TCKT"];

      console.log(`${chainId}\tBytecode size\t${TCKT.evm.bytecode.object.length}`);

      compareAgainstFoundry(TCKT.evm.bytecode.object, chainId, wallet.address);

      const factory = new ethers.ContractFactory(TCKT.abi, TCKT.evm.bytecode.object, wallet);
      const deployTransaction = factory.getDeployTransaction();
      const gasPromise = provider.estimateGas(deployTransaction.data);
      const gasPricePromise = provider.getGasPrice();
      Promise.all([gasPromise, gasPricePromise])
        .then(([gas, gasPrice]) => {
          const gasPriceStr = ethers.utils.formatUnits(gasPrice, "gwei");
          console.log(`${chainId}\t\tgas: ${gas.toBigInt()} x ${gasPriceStr} gwei`);
        })
    })
}

const Foundry = parse(readFileSync("foundry.toml")).profile.default;

/**
 * @param {string} privKey
 */
const deployToAllChains = (privKey) => {
  const wallet = new ethers.Wallet(privKey);
  const deployedAddress = ethers.utils.getContractAddress({
    from: wallet.address,
    nonce: 0
  });
  // Yerli ve milli
  if (!deployedAddress.startsWith("0xcCc") || !deployedAddress.endsWith("cCc")) {
    console.error("Deployed contract address failed check-sum. Check private key");
    process.exit(1);
  }
  console.log(
    "        TCKT Deployment\n" +
    "        -----------------\n" +
    `        Deployer address: ${wallet.address}\n` +
    `        Deployed address: ${deployedAddress}\n\n`);
  Object.keys(JsonRpcUrls).forEach((chainId) =>
    deployToChain(chainId, privKey));
}

deployToAllChains(
  process.argv[2] || "32ad0ed30e1257b02fc85fa90a8179241cc38d926a2a440d8f6fbfd53b905c33");
