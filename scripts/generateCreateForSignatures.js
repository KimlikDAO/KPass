/**
 * @see https://eips.ethereum.org/EIPS/eip-2098
 *
 * @param {string} signature of length 2 + 64 + 64 + 2 = 132
 * @return {string} compactSignature as a string of length 128 (64 bytes).
 */
const compactSignature = (signature) => {
  /** @const {boolean} */
  const yParity = signature.slice(-2) == "1c";
  signature = signature.slice(2, -2);
  if (yParity) {
    /** @const {string} */
    const t = (parseInt(signature[64], 16) + 8).toString(16);
    signature = signature.slice(0, 64) + t + signature.slice(65, 128);
  }
  return signature;
}

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

const KPASSDomain = {
  "name": "KPASS",
  "version": "1",
  "chainId": "0x144",
  "verifyingContract": KPASS
};

const USDCDomain = {
  "name": "USDC",
  "version": "1",
  "chainId": "0x144",
  "verifyingContract": USDC
};

const CreateForData = {
  "types": {
    EIP712Domain,
    "CreateFor": [
      { "name": "handle", "type": "uint256" },
    ]
  },
  "domain": KPASSDomain,
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
  const sig = compactSignature(wideSignature);
  console.log(`${name} signature:`)
  console.log("0x" + sig.slice(0, 64) + ",\n" + "0x" + sig.slice(64));
};

await signWithInjectedWallet(OWNER, CreateForData)
  .then((wideSignature) => printSignature("CreateFor", wideSignature));

await signWithInjectedWallet(OWNER, PermitData)
  .then((wideSignature) => printSignature("Permit", wideSignature));
