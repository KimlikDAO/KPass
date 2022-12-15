import { ethers } from "ethers";
import { readFileSync } from "fs";
import solc from "solc";
import { parse } from "toml";

/**
 * @param {string} file
 * @param {string} chainId
 */
const processTCKT = (file, chainId) => chainId == "0xa86a"
  ? file
  : file.slice(0, file.indexOf("// Exposure report") - 92) + "}";

/**
 * @param {Array<string>} sourceNames
 * @param {string} chainId
 */
const readSources = (sourceNames, chainId) => Object.fromEntries(
  sourceNames.map((name) => {
    const file = readFileSync(name.startsWith("interfaces")
      ? "lib/interfaces/contracts" + name.slice(10)
      : "contracts/" + name, "utf-8"
    );
    return [
      name,
      { content: name == "TCKT.sol" ? processTCKT(file, chainId) : file }
    ]
  })
)

/**
 * @param {string} chainId
 * @param {ethers.Wallet} signer
 */
const deployToChain = (chainId, signer) => {
  const compilerInput = {
    language: "Solidity",
    sources: readSources([
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

const Foundry = parse(readFileSync("foundry.toml")).profile.default;

// new ethers.Wallet(process.argv[2])
deployToChain("0x1", null);
