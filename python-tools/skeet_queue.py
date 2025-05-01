import hashlib
import json
import os
from pathvalidate import sanitize_filename

statuses = ['ignored', 'payload', 'payload_retry', 'tx', 'tx_retry', 'report', 'report_retry', 'abandoned', 'completed']

QUEUE_ROOT = "skeet_queue"

def prepare():
    if not os.path.exists(QUEUE_ROOT):
        os.mkdir(QUEUE_ROOT)
    for s in statuses:
        if not os.path.exists(QUEUE_ROOT + '/' + s):
            os.mkdir(QUEUE_ROOT + '/' + s)

def hashedName(at_uri, bot):
    fn = bot + '-' + at_uri
    return sanitize_filename(fn)

def status(at_uri, bot):
    # refer to posts by their uri hash to avoid dealing with untrusted filesystem paths
    fn = hashedName(at_uri, bot)
    for s in statuses:
        if os.path.exists(QUEUE_ROOT + '/' + s + '/' + fn):
            return s
    return None

def markIgnored(at_uri, bot):
    fn = hashedName(at_uri, bot)
    item = {
        "atURI": at_uri,
        "botName": bot
    }
    with open(QUEUE_ROOT + '/ignored/' + fn, 'w') as f:
        json.dump(item, f, indent=4)

def queueForPayload(at_uri, bot):
    fn = hashedName(at_uri, bot)
    item = {
        "atURI": at_uri,
        "botName": bot 
    }
    with open(QUEUE_ROOT + '/payload/' + fn, 'w') as f:
        json.dump(item, f, indent=4)

def updateStatus(at_uri, bot, from_status, to_status, new_content=None):
    fn = hashedName(at_uri, bot)
    os.rename(QUEUE_ROOT + '/' + from_status + '/' + fn, QUEUE_ROOT + '/' + to_status + '/' + fn)
    if new_content is not None:
        with open(QUEUE_ROOT + '/' + to_status + '/' + fn, 'w') as f:
            json.dump(new_content, f, indent=4)

def readNext(status):
    items = os.listdir(QUEUE_ROOT + '/' + status)
    if len(items) == 0:
        return None
    with open(QUEUE_ROOT + '/' + status + '/' + items[0]) as f:
        return json.load(f)

def readItem(at_uri, bot, status):
    fn = hashedName(at_uri, bot)
    with open(QUEUE_ROOT + '/' + status + '/' + fn) as f:
        return json.load(f)
