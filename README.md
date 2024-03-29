## KPASS: KimlikDAO Pass

<img align="right" width="300" height="300" src="https://kimlikdao.org/TCKT.svg">
KPASS is a decentralized identifier (DID) NFT which can be minted by
interacting with the KimlikDAO protocol. To interact with the protocol,
one can use the reference dApp deployed at https://kimlikdao.org or run the
dApp locally by cloning the repo https://github.com/KimlikDAO/dapp and
following the instructions therein.

The contents of each KPASS is cryptographically committed to a single wallet
address, making it unusable from any other address.
KPASS implements most of the ERC-721 NFT interface excluding, notably, the
transfer-related methods, since KPASSs are non-transferrable.

The contents of a KPASS are encrypted by the owners private keys in their
browser and then stored on the IPFS compatible storage layer of the KimlikDAO
protocol. The reason we do not use the IPFS network but a compatible
subnetwork run by KimlikDAO protocol nodes is that some jurisdictions
require personal information to be stored in certain geo locations, even
if the data is encrypted and even if it's encrypted by the user themselves.
IPFS protocol is not designed to respect such restrictions, whereas the
KimlikDAO protocol nodes will always honor these restrictions.

Further, KimlikDAO nodes will stop persisting the contents of a KPASS if
the owner revokes the KPASS using the `revoke()` method of this contract,
giving the user the freedom to delete their persisted data at any time
(even though the user data is encrypted on the user side)

### Minting

One can mint a KPASS by using the various flavors of the
[`create()`](https://github.com/KimlikDAO/KPASS/blob/main/contracts/KimlikDAOPass.sol#L192-L196) method.
These methods differ in the payment type and whether a revoker list is
included. A discount is offered for including a revoker list, which
increases security as explained below.

### Revoking

A KPASS owner may call the `revoke()` method of KPASS at any time to revoke
it, thereby making it unusable. This is useful, for example, when a user
gets their wallet private keys stolen.

### Social revoking

When minting a KPASS, you can nominate 3-5 addresses as revokers and assign
each a weight. If enough of these addresses vote to revoke the KPASS, it will
be revoked and become unusable.

This feature is useful in the event that your wallet private keys are stolen
and, further, you no longer have access to them. In such circumstances, you
can inform the nominated revokers and request them to cast a revoke vote.

To encourage setting up social revoke, a discount of 33% is offered
initially, and the discount rate is determined by the DAO vote thereafter.
The discount rate is set through the [`updatePricesBulk()`](https://github.com/KimlikDAO/KPASS/blob/main/contracts/KimlikDAOPass.sol#L672-L687)
method, which can only be called by
[`VOTING`](https://github.com/KimlikDAO/Voting), the KimlikDAO voting contract.

### Exposure report

In the case a KPASS holder

1. gets their private keys stolen, and
2. lose access to the keys themselves, and
3. did not set up social revoke when minting the KPASS,

there is one final way of disabling the stolen KPASS. The victim mints a new
KPASS and submits the `exposureReport` that comes with it to the
[`reportExposure()`](https://github.com/KimlikDAO/KPASS/blob/main/contracts/KimlikDAOPass.sol#L737-L776)
method of this contract. Doing so will disable _all_
previous KPASSs across _all chains_ belonging to this person. For convenience,
one may use the interface at https://kimlikdao.org/revoke to submit the
`exposureReport` to the KPASS contract.

### Modifying the revoker list

One can add new revokers, increase the weight of existing revokers or reduce
the revoke threshold after minting their KPASS by using the corresponding
methods of this contract. Removing a revoker is not
possible since it would allow an attacker having access to user private keys to
remove all revokers.

### Pricing and payments

The price of a KPASS is set by the `updatePrice()` or the `updatedPricesBulk()`
methods, which can only be called by `VOTING`, the KimlikDAO voting
contract.
Fees collected as an ERC-20 token are transferred directly to the
[`PROTOCOL_FUND`](https://github.com/KimlikDAO/ProtocolFund), the KimlikDAO
treasury and fees collected in the native token are accumulated in this
contract first and then swept to
[`PROTOCOL_FUND`](https://github.com/KimlikDAO/ProtocolFund) periodically.
The sweep mechanism was put in place to minimize the gas cost of minting a
KPASS. The sweep is completely permissionless; anyone can call the
`sweepNativeToken()` to transfer the native token balance over to
[`PROTOCOL_FUND`](https://github.com/KimlikDAO/ProtocolFund).
Further, weekly sweeps are done by KimlikDAO automation, covering the gas fee.
