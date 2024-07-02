import evm from "@kimlikdao/lib/ethereum/evm";

const OWNER = "0x79883D9aCBc4aBac6d2d216693F66FcC5A0BcBC1";
const KPASS = "0xcCc0a9b023177549fcf26c947edb5bfD9B230cCc";
const USDC = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";

/**
 * @const {!Array<!Object<string, string>>}
 */
const EIP712Domain = [
  { "name": "name", "type": "string" },
  { "name": "version", "type": "string" },
  { "name": "chainId", "type": "uint256" },
  { "name": "verifyingContract", "type": "address" },
];

const KPassDomain = {
  "name": "KPASS",
  "version": "1",
  "chainId": "0x1",
  "verifyingContract": KPASS
};

const USDCDomain = {
  "name": "USDC",
  "version": "1",
  "chainId": "0x1",
  "verifyingContract": USDC
};

const CreateForData = {
  "types": {
    EIP712Domain,
    "CreateFor": [
      { "name": "handle", "type": "uint256" },
    ]
  },
  "domain": KPassDomain,
  "primaryType": "CreateFor",
  "message": {
    "handle": "0x1337ABCDEF"
  }
};

const PermitData = {
  "types": {
    EIP712Domain,
    "Permit": [
      { "name": "owner", "type": "address" },
      { "name": "spender", "type": "address" },
      { "name": "value", "type": "uint256" },
      { "name": "nonce", "type": "uint256" },
      { "name": "deadline", "type": "uint256" }
    ]
  },
  "domain": USDCDomain,
  "primaryType": "Permit",
  "message": {
    "owner": OWNER,
    "spender": KPASS,
    "value": "0x" + BigInt("3000000").toString(16),
    "nonce": 0,
    "deadline": 123456
  }
}

const signWithInjectedWallet = (address, data) => window.ethereum.request({
  "method": "eth_signTypedData_v4",
  "params": [address, JSON.stringify(data)]
});

const printSignature = (name, wideSignature) => {
  const sig = evm.compactSignature(wideSignature);
  console.log(`${name} signature:`)
  console.log("0x" + sig.slice(0, 64) + ",\n" + "0x" + sig.slice(64));
};

await signWithInjectedWallet(OWNER, CreateForData)
  .then((wideSignature) => printSignature("CreateFor", wideSignature));

await signWithInjectedWallet(OWNER, PermitData)
  .then((wideSignature) => printSignature("Permit", wideSignature));
