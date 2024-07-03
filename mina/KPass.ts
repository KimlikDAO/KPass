import {
  AccountUpdate,
  Field,
  MerkleWitness,
  SmartContract,
  State,
  method,
  state,
} from "o1js";

const KPASS = "B62qnnFm3SEtrMgStoj4SRVxKSTERh8Ho3Y9jCCa8TvgBF1mqa97Sij";

const MINA = 1e9; // 30 bits, safe int

class KPassWitness extends MerkleWitness(256) { }

class KPass extends SmartContract {
  @state(Field) handlesRoot = State<Field>();
  @state(Field) noncesRoot = State<Field>();

  /**
   * @param {!Field} handle IPFS hash of the KPass contents.
   * @param {!KPassWitness} witness MerkleWitness to the senders address.
   */
  @method
  async create(handle: Field, witness: KPassWitness) {
    const sender = this.sender.getAndRequireSignature();
    const senderUpdate = AccountUpdate.create(sender);
    senderUpdate.requireSignature();
    senderUpdate.send({ to: this, amount: 1 * MINA })
    witness
      .calculateIndex()
      .assertEquals(
        sender.x.add(sender.isOdd.toField()),
        "Witness does not match tx.sender"
      );
    const handlesRoot = this.handlesRoot.getAndRequireEquals();
    handlesRoot.assertEquals(
      witness.calculateRoot(Field(0)),
      "Invalid witness or handleOf[sender] is already set. Use the `update()` method."
    );
    this.handlesRoot.set(witness.calculateRoot(handle));
  }

  /**
   * @param {!Field} newHandle New IPFS hash of the KPass contents.
   * @param {!Field} oldHandle Old IPFS hash of the KPass, to be udpated.
   * @param {!KPassWitness} witness MerkleWitness to the senders address.
   */
  @method
  async update(newHandle: Field, oldHandle: Field, witness: KPassWitness) {
    const sender = this.sender.getAndRequireSignature();
    oldHandle.assertNotEquals(0, "Initial write requires payment");
    witness
      .calculateIndex()
      .assertEquals(
        sender.x.add(sender.isOdd.toField()),
        "Witness does not match tx.sender"
      );
    const handlesRoot = this.handlesRoot.getAndRequireEquals();
    handlesRoot.assertEquals(
      witness.calculateRoot(oldHandle),
      "Invalid witness."
    );
    this.handlesRoot.set(witness.calculateRoot(newHandle));
  }
}

export { KPASS, KPass };
