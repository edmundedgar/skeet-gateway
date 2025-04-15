# Signers and Safes

The following is only partly implemented as of 2025-01-02.

## Signers

You are identified by the key you are signing skeets with.

## Safes

Signer Safes are created by the gateway.

If you try to perform some action without already having a Signer Safe created and selected, the SkeetGateway will create one for you. Any action taken by your signer will then be sent as a transaction by that Safe.

This Signer Safe is a safe.global Safe with the SkeetGateway added as its first (and only) owner. The Signer Safe will only send commands to the Safe owned by the person who signed a skeet, so the fact that your Safe receives a message from the SkeetGateway means that the message is legitimate.

(implemented)

### Adding and selecting a Signer Safe

Normally you probably only want a single Signer Safe. But if you want another one, you can create it and select it with:
```
@create.safe.skeetbot.eth.link new
```

Once you have more than one Signer Safe, you can switch between them, eg:
`@select.safe.skeetbot.eth.link 2` where 2 is the index of your third safe.

(not yet implemented)

### Adding an extra key to a Signer Safe

You can add a key to an existing Signer Safe with
`@addkey.skeetbot.eth.link 0xdeadbeef`

This will then allow you to control your Signer Safe through a traditional method, eg the safe.global UI, as well as by sending skeets. You can also use this UI to change the threshold for signatures, for example you may require that assets can only be spent if you send the skeet, and also provide a traditional signature.

If a Safe needs more than one key, the SkeetGateway will stop executing transactions directly and instead call the `approveHash` method. You can then execute it from the web UI once the same transaction has gathered enough signatures.

It is technically possible to use the safe.global UI to remove access to the SkeetGateway. If you do this, your Signer Safe will no longer act on your skeets. You can later add a new Signer Safe that will.

(implemented)

### Using an existing Safe

If you already have a Safe, you can control it with your Signer as follows:

1) Add your Signer Safe as an account controlling it
2) `@operate.safe.skeetbot.eth.link 2 0xSafeAddress` where 0xSafeAddress is the address of your existing safe and 2 is the index of your Signer Safe.

Any further actions will then be sent first through your gateway-created Safe, then sent on to your pre-existing safe.

(not yet implemented)

## The Safe Directory

If someone wants to know your Safe address so they can send you something or give you permission for something, they can query the SkeetGateway. This will also be used by bots, eg if you try to send a payment to @goat.navy a bot will look up the Safe for that Signer and tell you its address, prompting you to agree to a message to send the payment.

If you do not yet have a Safe registered with the SkeetGateway, it will tell you the address of the #0 Gateway-created Safe. This allows you to send assets to it before the user who will own it makes their first skeet.

(implemented in contract, no ui)

## Upgrading the SkeetGateway

To remain trustless, the SkeetGateway has no admin backdoor. We cannot upgrade it. But we may publish a new version of the SkeetGateway.

As far as the Safe is concerned the SkeetGateway is simply another owner account, so you can upgrade to a new SkeetGateway by adding the new SkeetGateway as an owner of the existing Safe and selecting it with the new SkeetGateway.

We may publish a new bot for upgrading with our new SkeetGateway address already set and attach it to the old SkeetGateway, so that if you choose to upgrade you can message

```
upgrade.skeetbot.eth.link
```

The old SkeetGateway will interpret this by adding the address of the new SkeetGateway to the existing Safe, and the new SkeetGateway will interpret it by selecting the existing Safe in use by the old SkeetGateway.

(not yet implemented)

## Key rotation

The contract cannot automatically follow DID directory updates because the validity of updates depends on the order in which they are received, which cannot be trustlessly verified. So for example, if one of the early rotation keys was compromised, and the contract has not received the message about this, it could be used to steal accounts at a later date.

However, if possible we want to avoid people losing access to their accounts if they forget to add a signer before migrating server.

We therefore allow keys to be changed in the following ways:

1. Manually adding and removing. Any signer can add or remove keys for that account without reference to DID updates. You can lock accidentally yourself out by this method, although you may be able to rescure the situation with method (3) below.

eg `addsigner.skeetbot.eth.link 0xdeaddeef` adds the key `0xdeaddeef` as a controller of the account.

2. Opt-in DID updates. A signer in control of the account can skeet the most recent revision of your DID that they accept, and optionally a deadline. Until that deadline, the first revision by keys in the current version of the directory will be accepted on receipt. You can change this policy at any time with another skeet, as long as your signer has not already been removed by DID updates.

eg `did.skeetbot.eth.link bafyreifbilrkm7ktlamiqslrjq33bbnhs6pj4pstasnpg4ly5mimmjxjam 2025-02-25`
...declares the final revision shown at https://plc.directory/did:plc:pyzlzqt6b2nyrha7smfry6rv/log/audit to be valid for that signer, and will accept and apply any DID message in the order received until 2025-02-25.

3. Uncontested DID updates. If a DID message is published, and no conflicting message is published within 96 hours, it will be accepted and any other keys specified in the DID usable for the same account. If you have specified a previous revision with `did.skeetbot.eth.link`, only messages subsequent to that will be accepted. Note that if your early rotation keys were compromised and you have not since specified a DID revision, an attacker will have the ability to stop this method working for you, until such time as you do specify a DID revision after the conflicting messages.
