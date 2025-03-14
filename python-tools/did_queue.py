import hashlib
import json
import os

statuses = ['payload', 'payload_retry', 'tx', 'tx_retry', 'report', 'report_retry', 'abandoned', 'completed']

QUEUE_ROOT = "did_queue"

def prepare():
    if not os.path.exists(QUEUE_ROOT):
        os.mkdir(QUEUE_ROOT)
    for s in statuses:
        if not os.path.exists(QUEUE_ROOT + '/' + s):
            os.mkdir(QUEUE_ROOT + '/' + s)

def hashedName(did):
    return hashlib.sha256(did.encode()).hexdigest()

def status(did):
    # refer to posts by their uri hash to avoid dealing with untrusted filesystem paths
    fn = hashedName(did)
    for s in statuses:
        if os.path.exists(QUEUE_ROOT + '/' + s + '/' + fn):
            return s
    return None

def queueForPayload(did):
    fn = hashedName(did)
    item = {
        "did": did
    }
    with open(QUEUE_ROOT + '/payload/' + fn, 'w') as f:
        json.dump(item, f, indent=4)

def updateStatus(did, from_status, to_status, new_content=None):
    fn = hashedName(did)
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
