## Shadow DID contract

## What this does

The Shadow DID contract maintains a tree of correctly-signed updates to DID:PLC records.

It can be updated by calling `registerUpdates()` with signed messages from the DID:PLC audit log.

In most cases this will result in the current DID:PLC update for the user, matching the one listed at http://plc.directory.

You can query this update with `ShadowDidPLCDirectory.uncontroversialTip(bytes32 did)`.

To get the corresponding atproto key, you can call `ShadowDidPLCDirectory.uncontroversialVerificationAddress(bytes32 did)`.

In some cases, there may be multiple forks of correctly-signed messages. This can happen in the following cases:

 * You make an update, then within 72 hours replace it with another update, signed with a higher-priority key. This will result in plc.directory invalidating the earlier record.
 * You publish an update changing to a new rotation key, but someone gets hold of your old key and maliciously signs messages with it. The later messages should be ignored by plc.directory, but this contract will be unable to tell which one was real
 * Likewise, but the plc.directory maliciously chooses the attacker fork, not the fork that it received earlier, so the version at plc.directory is incorrect. In this situation it may be possible to make a reasonable claim about that the state of the directory should be really, or there may be no unambiguously correct answer available.


## Getting started

Make a .env with `PRIVATE_KEY`, `SEPOLIA_RPC_URL` and (for deployments) `ETHERSCAN_API_KEY` then run:

```
   source .env
```

Run `forge build`.

## Deployment

```
forge script --chain sepolia script/DeployShadowDIDPLCDirectory.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify
```

## Sending an update

Prepare the update with `python-tools/prepare_did_update.py` and put it in `test/fixtures/did`.

```
forge script --chain sepolia script/SendShadowDIDUpdate.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --sig 'run(address,string)' $SHADOW_DID did:plc:pyzlzqt6b2nyrha7smfry6rv.json --broadcast
```
