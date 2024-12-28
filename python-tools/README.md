# Python tools

Python tools used for fetching skeets that need to be handled by the SkeetGateway and calling handleSkeet for them.

They may later be replaced by our (better quality) Typescript code under `bot/`.

## Preparation

```
python3 -m venv ~/venv/skeet-gateway
source ~/venv/skeet-gateway/bin/activate
pip install -r requirements.txt 
```

Copy `env.sample` to `.env` and fill in the details.

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

