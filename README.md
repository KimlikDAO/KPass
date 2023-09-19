## TCKT: KimlikDAO DID Token

<img align="right" width="300" height="300" src="https://kimlikdao.org/TCKT.svg">
TCKT is a decentralized identifier (DID) NFT which can be minted by
interacting with the KimlikDAO protocol. To interact with the protocol,
one can use the reference dApp deployed at https://kimlikdao.org or run it
locally by cloning the repo https://github.com/KimlikDAO/dapp and following
the instructions therein.

The contents of each TCKT is cryptographically committed to a single EVM
address, making it unusable from any other address.
TCKT implements most of the ERC-721 NFT interface excluding, notably, the
transfer-related methods, since TCKTs are non-transferrable.

The contents of a TCKT are encrypted by the owners private keys in their
browser and then stored on the IPFS compatible storage layer of the KimlikDAO
protocol. The reason we do not use the IPFS network but a compatible
subnetwork run by KimlikDAO protocol nodes is that some jurisdictions
require personal information to be stored in certain geo locations, even
if the data is encrypted and even if it's encrypted by the user themselves.
IPFS protocol is not designed to respect such restrictions, whereas the
KimlikDAO protocol nodes will always honor these restrictions.

Further, KimlikDAO nodes will stop persisting the contents of a TCKT if
the owner revokes the TCKT using the `revoke()` method of this contract,
giving the user the freedom to delete their persisted data at any time
(even though the user data is encrypted on the user side)

### Minting

One can mint a TCKT by using the various flavors of the [`create()`](https://github.com/KimlikDAO/TCKT/blob/main/contracts/TCKT.sol#L192-L196) method.
These methods differ in the payment type and whether a revoker list is
included. A discount is offered for including a revoker list, which
increases security as explained below.

### Revoking

A TCKT owner may call the `revoke()` method of TCKT at any time to revoke
it, thereby making it unusable. This is useful, for example, when a user
gets their wallet private keys stolen.

### Social revoking

When minting a TCKT, you can nominate 3-5 addresses as revokers and assign
each a weight. If enough of these addresses vote to revoke the TCKT, it will
be revoked and become unusable.

This feature is useful in the event that your wallet private keys are stolen
and, further, you no longer have access to them. In such circumstances, you
can inform the nominated revokers and request them to cast a revoke vote.

To encourage setting up social revoke, a discount of 33% is offered
initially, and the discount rate is determined by the DAO vote thereafter.
The discount rate is set through the [`updatePricesBulk()`](https://github.com/KimlikDAO/TCKT/blob/main/contracts/TCKT.sol#L672-L687)
method, which can only be called by
[`OYLAMA`](https://github.com/KimlikDAO/Oylama), the KimlikDAO voting contract.

### Exposure report

In the case a TCKT holder

1. gets their private keys stolen, and
2. lose access to the keys themselves, and
3. did not set up social revoke when minting the TCKT,

there is one final way of disabling the stolen TCKT. The victim mints a new
TCKT and submits the `exposureReport` that comes with it to the
[`reportExposure()`](https://github.com/KimlikDAO/TCKT/blob/main/contracts/TCKT.sol#L737-L776)
method of this contract. Doing so will disable _all_
previous TCKTs across _all chains_ belonging to this person. For convenience,
one may use the interface at https://kimlikdao.org/revoke to submit the
`exposureReport` to the TCKT contract.

### Modifying the revoker list

One can add new revokers, increase the weight of existing revokers or reduce
the revoke threshold after minting their TCKT by using the corresponding
methods of this contract. Removing a revoker is not
possible since it would allow an attacker having access to user private keys to
remove all revokers.

### Pricing and payments

The price of a TCKT is set by the `updatePrice()` or the `updatedPricesBulk()`
methods, which can only be called by `OYLAMA`, the KimlikDAO voting
contract.
Fees collected as an ERC-20 token are transferred directly to the
[`DAO_KASASI`](https://github.com/KimlikDAO/DAOKasasi), the KimlikDAO treasury
and fees collected in the native token
are accumulated in this contract first and then swept to [`DAO_KASASI`](https://github.com/KimlikDAO/DAOKasasi)
periodically. The sweep mechanism was put in place to minimize the gas cost
of minting a TCKT. The sweep is completely permissionless; anyone can call
the `sweepNativeToken()` to transfer the native token balance over to
[`DAO_KASASI`](https://github.com/KimlikDAO/DAOKasasi).
Further, weekly sweeps are done by KimlikDAO automation, covering the gas fee.
