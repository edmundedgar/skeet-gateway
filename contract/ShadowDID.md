## Shadow DID contract

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
