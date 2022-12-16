import { ethers } from "ethers";
import { readFileSync } from "fs";
import solc from "solc";
import { parse } from "toml";

/**
 * @param {string} file
 * @param {string} chainId
 */
const processTCKT = async (file, chainId) => {
  file = file.replace(
    "0x8730afd3d29f868d9f7a9e3ec19e7635e9cf9802980a4a5c5ac0b443aea5fbd8",
    await computedDomainSeparator(chainId))
  return chainId == "0xa86a"
    ? file
    : file.slice(0, file.indexOf("// Exposure report") - 92) + "}";
}
/**
 * @param {Array<string>} sourceNames
 * @param {string} chainId
 */
const readSources = (sourceNames, chainId) => processTCKT(
  readFileSync('./contracts/TCKT.sol', 'utf-8'), chainId)
  .then((tcktFile) => Object.fromEntries(
    sourceNames.map((name) => {
      return [
        name, {
          content: name == "TCKT.sol" ? tcktFile : readFileSync(name.startsWith("interfaces")
            ? "lib/interfaces/contracts" + name.slice(10)
            : "contracts/" + name, "utf-8"
          )
        }
      ]
    }))
  )

/**
 * @param {string} chainId
 * @param {ethers.Wallet} signer
 */
const deployToChain = async (chainId, signer) => {
  const compilerInput = {
    language: "Solidity",
    sources: await readSources([
      "IDIDSigners.sol",
      "interfaces/Addresses.sol",
      "interfaces/IERC20.sol",
      "interfaces/IERC20Permit.sol",
      "interfaces/IERC721.sol",
      "TCKT.sol",
    ], chainId),
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

/**
 * @param {string} chainId
 * @return {Promise<string>}
 */
const computedDomainSeparator = (chainId) => {
  return ethers.utils._TypedDataEncoder.hashDomain({
    name: 'TCKT',
    version: '1',
    chainId,
    verifyingContract: '0xcCc0F938A2C94b0fFBa49F257902Be7F56E62cCc'
  });
}

const Foundry = parse(readFileSync("foundry.toml")).profile.default;

// new ethers.Wallet(process.argv[2])
deployToChain("0x1", null);