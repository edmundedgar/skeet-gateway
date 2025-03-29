# Python tools

Python tools used for fetching skeets that need to be handled by the SkeetGateway and calling handleSkeet for them.

## Preparation

```
python3 -m venv ~/venv/skeet-gateway
source ~/venv/skeet-gateway/bin/activate
pip install -r requirements.txt 
```

Copy `env.sample` to `.env` and fill in the details.

## What this does

There is a script for each step in handling a skeet that needs to be sent to the blockchain.

The skeets to handle at each step are managed in a directory under `queue` (for SkeetGateway updates) or `did_queue` (for ShadowPLCDirectory updates).

The queues go: `payload` -> `tx` -> `report` -> `completed`.

If an error occurs that may not be fatal they will be moved into the `_retry` version, eg `payload_retry`.

The scripts consist of:
 
### Setup

  * `load_bots.py` creates a record of any bots registered with the `SkeetGateway`.

### Skeet Gateway

  * `fetch_skeets.py` fetches any skeets addressed to the bots on the list and queues them for payload fetching.
  * `prepare_payload.py` fetches the payload (merkle proof etc) and formats it ready to be sent to the chain.
  * `send_tx.py` simulates the transaction, and sends it to the blockchain
  * `report_tx.py` creates a reply skeet telling the user what happened

### Skeet Gateway

  * `find_active_dids.py` makes a list of atproto accounts that are active on the blockchain and therefore may need their DID data recorded in the Shadow DID registry.
  * `watch_did_update.py` checks for any updates to the active did records that may need to be sent to the blockchain.
  * `prepare_did_update.py` fetches the update history and formats it ready to be sent to the blockchain.
  * `send_did_tx.py` simulates the transaction to update the registry and sends it to the blockchain.
  * `report_did_tx.py` has not been implemented yet so DID updates just pile up in the `report` queue.

To run all these scripts in order, run `./handle.sh`.


## Usage

### Loading bot configurations

Ensure you have an up-to-date list of bots in `parser_config.json` by running:

```
python load_bots.py
```

This will scan through blocks starting at the most recent. You can kill the process once you think you've got everything. It will not need to be updated unless someone registers a new bot.

### Fetching skeets addressed to the bots

```
python fetch_skeets.py
```

This will use the search API to find any unhandled skeets addressed to the bots in `parser_config.json` and queue them for the payload handling script.

### Preparing payloads

```
python prepare_payload.py
```

This will create payloads for any unhandled skeets fetched in the previous step ready to be sent to the chain. If successful it will move them from the "payload" queue to the "tx" queue.

You can also run this script to create a payload for an individual skeet, for example to create a test fixture:

```
python prepare_payload.py <at://...>
```
eg 

```
python prepare_payload.py at://did:plc:pyzlzqt6b2nyrha7smfry6rv/app.bsky.feed.post/3ldil5zogd22a
```

For publicly shared posts it can also handle a bsky.app URL, eg you can get a payload for the same record with

```
python prepare_payload.py https://bsky.app/profile/goat.navy/post/3ldil5zogd22a
```

The script will cache data downloaded in the process of generating this record. Note that if you delete the cache and rerun it, the content of the resulting JSON file may be different as the MST tree may have changed, although either version should work.

### Sending transactions to the chain

```
python send_tx
```

This will attempt to send any unhandled transactions to the chain and move them to `completed` status. Some transactions may revert during gas estimation. For example, someone may have sent a payment but not have enough funds in the sender account. These will be moved to the `tx_retry` queue.

