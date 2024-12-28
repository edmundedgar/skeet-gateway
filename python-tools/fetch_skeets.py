import os
from atproto import Client
from dotenv import load_dotenv
import json

import skeet_queue

parsers = {}
with open('parser_config.json') as f:
    parsers = json.load(f)

load_dotenv()

BSKY_SEARCH_API_USER = os.getenv('BSKY_SEARCH_API_USER')
BSKY_SEARCH_API_KEY = os.getenv('BSKY_SEARCH_API_KEY')

client = Client()
profile = client.login(BSKY_SEARCH_API_USER, BSKY_SEARCH_API_KEY)
print('Welcome,', profile.display_name)

for handle in parsers:
    posts = client.app.bsky.feed.search_posts({"q": handle})
    for p in posts['posts']:
        status = skeet_queue.status(p.uri, handle)
        if status is None:
            skeet_queue.queueForPayload(p.uri, handle)
            print("Queued: "+p.uri + " (" + handle + ") ")
