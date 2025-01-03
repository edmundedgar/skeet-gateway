# Signers and Safes

The following is only partly implemented as of 2025-01-02.

## Signers

You are identified by the key you are signing skeets with.

## Safes

Signer Safes are created by the gateway.

If you try to perform some action without already having a Signer Safe created and selected, the SkeetGateway will create one for you. Any action taken by your signer will then be sent as a transaction by that Safe.

This Signer Safe is a safe.global Safe with the SkeetGateway added as its first (and only) owner. The Signer Safe will only send commands to the Safe owned by the person who signed a skeet, so the fact that your Safe receives a message from the SkeetGateway means that the message is legitimate.

### Adding and selecting a Signer Safe

Normally you probably only want a single Signer Safe. But if you want another one, you can create it and select it with:
```
@create.safe.skeetgateway.eth.link new
```

Once you have more than one Signer Safe, you can switch between them, eg:
`@select.safe.skeetgateway.eth.link 2` where 2 is the index of your third safe.

### Adding an extra key to a Signer Safe

You can add a key to an existing Signer Safe with
`@add.key.safe.skeetgateway.eth.link 0xdeadbeef`

This will then allow you to control your Signer Safe through a traditional method, eg the safe.global UI, as well as by sending skeets. You can also use this UI to change the threshold for signatures, for example you may require that assets can only be spent if you send the skeet, and also provide a traditional signature.

It is technically possible to use the safe.global UI to remove access to the SkeetGateway. If you do this, your Signer Safe will no longer act on your skeets. You can later add a new Signer Safe that will.


### Using an existing Safe

If you already have a Safe, you can control it with your Signer as follows:

1) Add your Signer Safe as an account controlling it
2) `@operate.safe.skeetgateway.eth.link 2 0xSafeAddress` where 0xSafeAddress is the address of your existing safe and 2 is the index of your Signer Safe.

Any further actions will then be sent first through your gateway-created Safe, then sent on to your pre-existing safe.


## The Safe Directory

If someone wants to know your Safe address so they can send you something or give you permission for something, they can query the SkeetGateway. This will also be used by bots, eg if you try to send a payment to @goat.navy a bot will look up the Safe for that Signer and tell you its address, prompting you to agree to a message to send the payment.

If you do not yet have a Safe registered with the SkeetGateway, it will tell you the address of the #0 Gateway-created Safe. This allows you to send assets to it before the user who will own it makes their first skeet.

## Upgrading the SkeetGateway

To remain trustless, the SkeetGateway has no admin backdoor. We cannot upgrade it. But we may publish a new version of the SkeetGateway.

As far as the Safe is concerned the SkeetGateway is simply another owner account, so you can upgrade to a new SkeetGateway by adding the new SkeetGateway as an owner of the existing Safe and selecting it with the new SkeetGateway.

We may publish a new bot for upgrading with our new SkeetGateway address already set and attach it to the old SkeetGateway, so that if you choose to upgrade you can message

```
upgrade.skeetgateway.eth.link
```

The old SkeetGateway will interpret this by adding the address of the new SkeetGateway to the existing Safe, and the new SkeetGateway will interpret it by selecting the existing Safe in use by the old SkeetGateway.

## Key rotation

If you migrate your account from one PDS to another, this will result in you being assigned new Signer keys. These are published to the DID directory.

You can migrate your account before this happens by adding the expected key as an owner of your Safe. Then when you show up with the new key, select that safe for the new signer.

The contract cannot automatically follow DID directory updates because the validity of updates depends on the order in which they are received. So for example, if one of the early rotation keys was compromised, and the contract has not received the message about this, it could be used to steal accounts at a later date.

The best we may be able to do is to make a DID-shadowing contract that manages possible forks of a DID history. You could then instruct the SkeetGateway that it should upgrade your Safe keys to follow any legal update of the the specified fork. 

eg `did.skeetgateway.eth.link bafyreifbilrkm7ktlamiqslrjq33bbnhs6pj4pstasnpg4ly5mimmjxjam 2`
...declares the final revision shown at https://plc.directory/did:plc:pyzlzqt6b2nyrha7smfry6rv/log/audit to be valid for that signer, and will accept the next 2 rotation messages from the rotation keys it specifies.
