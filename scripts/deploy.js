import { ethers } from "ethers";
import { readFileSync } from "fs";
import solc from "solc";
import { parse } from "toml";


/**
 * @typedef {{ content: string }}
 */
let SourceFile;

const jsonRpcList = {
  "0x1": ["cloudflare-eth.com", "Ethereum"],
  "0xa86a": ["api.avax.network/ext/bc/C/rpc", "Avalanche"],
  "0x89": ["rpc-mainnet.matic.network", "Polygon"],
  "0xa4b1": ["arb1.arbitrum.io/rpc", "Arbitrum"],
  "0x38": ["bsc-dataseed.binance.org", "BNB Chain"],
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
 * @param {!Object<string, !SourceFile>} sources
 * @param {string} chainId
 * @param {string} deployerAddress
 * @return {!Object<string, !SourceFile>}
 */
const processSources = (sources, chainId, deployerAddress) => {
  const deployedAddress = ethers.utils.getContractAddress({
    from: deployerAddress,
    nonce: 0
  });
  const domainSeparator = ethers.utils._TypedDataEncoder.hashDomain({
    name: 'TCKT',
    version: '1',
    chainId,
    verifyingContract: deployedAddress
  });
  let file = sources["TCKT.sol"].content;
  file = file.replace(
    "0x8730afd3d29f868d9f7a9e3ec19e7635e9cf9802980a4a5c5ac0b443aea5fbd8",
    domainSeparator);
  if (chainId == "0xa86a")
    file = file.slice(0, file.indexOf("// Exposure report") - 92) + "}";
  sources["TCKT.sol"].content = file;
  return sources;
}

/**
 * @param {string} chainId
 * @param {ethers.Wallet} signer
 */
const deployToChain = (chainId, signer) => {
  const deployerAddress = "0x0DabB96F2320A170ac0dDc985d105913D937ea9A";

  const compilerInput = {
    language: "Solidity",
    sources: processSources(readSources([
      "IDIDSigners.sol",
      "interfaces/Addresses.sol",
      "interfaces/IERC20.sol",
      "interfaces/IERC20Permit.sol",
      "interfaces/IERC721.sol",
      "TCKT.sol",
    ]), chainId, deployerAddress),
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

  if (chainId == "0xa86a") {
    const solcjsBytecode = TCKT.evm.bytecode.object;
    const foundryBytecode = JSON.parse(readFileSync("out/TCKT.sol/TCKT.json")).bytecode.object.slice(2);
    if (solcjsBytecode.slice(0, -86) != foundryBytecode.slice(0, -86)) {
      console.log("Bytecode differs from Foundry compiled one");
      process.exit(1);
    }
  }
  const factory = new ethers.ContractFactory(TCKT.abi, TCKT.evm.bytecode.object);
  console.log(factory);
}

const Foundry = parse(readFileSync("foundry.toml")).profile.default;

// new ethers.Wallet(process.argv[2])
deployToChain("0x1", null);