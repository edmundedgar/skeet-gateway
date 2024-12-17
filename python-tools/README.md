# Python tool

This is a quick-and-dirty tool used in prototyping to prepare a payload for the SkeetGateway handleSkeet function. 

It will probably be replaced by our (better quality) Typescript code under `bot/`.

## Preparation

```
python3 -m venv ~/venv/skeet-gateway
source ~/venv/skeet-gateway/bin/activate
pip install -r requirements.txt 
```

## Usage

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

It will spit out a JSON file for the specified DID and record under `out/`. 

The script will cache data downloaded in the process of generating this record. Note that if you delete the cache and rerun it, the content of the resulting JSON file may be different as the MST tree may have changed, although either version should work.
