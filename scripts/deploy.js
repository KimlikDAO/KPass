import { readFileSync } from "fs";
import solc from "solc";

const processTCKT = (file) => {
  return file;
}

/**
 * @param {Array<string>} sourceNames
 */
const readSources = (sourceNames) => Object.fromEntries(
  sourceNames.map((name) => {
    const file = readFileSync(name.startsWith("interfaces")
      ? "lib/interfaces/contracts" + name.slice(10)
      : "contracts/" + name, "utf-8"
    );
    return [
      name,
      { content: name == "TCKT.sol" ? processTCKT(file) : file }
    ]
  }
  )
)

const Input = {
  language: "Solidity",
  sources: readSources([
    "IDIDSigners.sol",
    "interfaces/Addresses.sol",
    "interfaces/IERC20.sol",
    "interfaces/IERC20Permit.sol",
    "interfaces/IERC721.sol",
    "TCKT.sol",
  ]),
}

console.log(solc.compile(JSON.stringify(Input)));
