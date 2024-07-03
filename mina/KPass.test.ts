import { Field, MerkleTree, Mina, PrivateKey, PublicKey, UInt64 } from "o1js";
import { KPass } from "./KPass";

describe("Example Airdrop zkApp", () => {
  let tree: MerkleTree;
  let senderKey: PrivateKey;
  let appKey: PrivateKey;
  let sender: PublicKey;
  let app: KPass;

  beforeAll(() => KPass.compile());

  beforeEach(() =>
    Mina.LocalBlockchain({ proofsEnabled: true }).then((local) => {
      tree = new MerkleTree(256);
      Mina.setActiveInstance(local);
      senderKey = local.testAccounts[0].key;
      sender = senderKey.toPublicKey();
      appKey = local.testAccounts[1].key;
      app = new KPass(appKey.toPublicKey());

      const deployerKey = local.testAccounts[2].key;
      const deployer = deployerKey.toPublicKey();
      return Mina.transaction(deployer, () => app.deploy())
        .prove()
        .sign([appKey, deployerKey])
        .send();
    })
  );

  it("should deploy the app", () =>
    console.log("Deployed KPass contract at", app.address.toBase58()));
});
