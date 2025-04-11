import web3
from eth_account import Account
import os
import json
import time
import sys

import hashlib

from atproto import Client, models, client_utils

import skeet_queue

from dotenv import load_dotenv

from web3._utils.events import get_event_data

DRY_RUN = False

load_dotenv(dotenv_path='../contract/.env')

skeet_queue.prepare()

url = os.getenv('SEPOLIA_RPC_URL')
w3 = web3.Web3(web3.HTTPProvider(url))

# Identifier in gnosis safe
CHAIN_NAME = 'sep'

# Copied our own abi files to abi/ with
# cp ../contract/out/*.sol/*.json abi/
# May also need abis not in this project
ABI_PATH = './abi/'

ABI_FILES = []

if not os.path.exists(ABI_PATH):
    print("Please create the abi/ directory and fill it with the ABIs you might need, eg with:")
    print("pushd ../contract && forge build && popd")
    print("mkdir abi && cp ../contract/out/*.sol/*.json abi/")
    sys.exit(1)

for f in os.listdir(ABI_PATH):
    f_path = os.path.join(ABI_PATH, f)
    if os.path.isfile(f_path):
        ABI_FILES.append(f_path)

bot_login = {}
with open("bot_login.json") as f:
    bot_login = json.load(f)

default_bot = None
for b in bot_login:
    if 'default' in bot_login[b] and bot_login[b]['default']:
        default_bot = b
        break

if default_bot is None:
    print('Could not find default bot. Please set "default": true for one entry in bot_login.json')
    sys.exit()

def processQueue():
    while True:
        item = skeet_queue.readNext("report")
        if item is None:
            break
        handleItem(item)

def handleItem(item):
    at_uri = item['atURI']
    # print("handle item " + at_uri)
    bot = item['botName']

    if 'x_tx_hash' not in item:
        skeet_queue.updateStatus(at_uri, bot, "report", "report_retry", item)
        print("Item without tx hash moved to report_retry")
        return

    txid = item['x_tx_hash']
    etherscan_uri = 'https://sepolia.etherscan.io/tx/' + txid

    tx = w3.eth.get_transaction(txid)
    receipt = w3.eth.get_transaction_receipt(txid)
    # print(receipt)

    log_reports = {}
    abi_contents = {}
    events_to_abi = {}

    found_events_by_name = {}

    for abi_file in ABI_FILES:
        with open(abi_file) as f:
            d = json.load(f)
            abi_contents[abi_file] = d['abi']

            for entry in d['abi']:
                if entry['type'] == 'event':
                    event = entry
                    name = event["name"]
                    inputs = [param["type"] for param in event["inputs"]]
                    inputs = ",".join(inputs)
                    event_signature_text = f"{name}({inputs})"
                    event_signature_hex = "0x" + w3.keccak(text=event_signature_text).hex()
                    #print(event_signature_hex)
                    events_to_abi[event_signature_hex] = {
                        'name': name,
                        'contract': abi_file,
                        'event': event,
                        'abi': d['abi']
                    }

    for l in receipt.logs:
        # Encode and decode back to change the binary stuff into hex
        log_obj = json.loads(w3.to_json(l))
        topic = log_obj['topics'][0]
        address = log_obj['address']

        if topic in events_to_abi:
            name = events_to_abi[topic]['name']
            event_data = get_event_data(w3.codec, events_to_abi[topic]['event'], l)
            found_events_by_name[name] = event_data


    send_as_bot = default_bot
    if bot in bot_login:
        send_as_bot = bot

    message = client_utils.TextBuilder()

    print(found_events_by_name.keys())

    # TODO: Should probably check signature IDs herea to avoid collisions
    # print(found_events_by_name)

    if 'LogCreateSafe' in found_events_by_name:
        addr = found_events_by_name['LogCreateSafe']['args']['accountSafe']
        safe_link = 'https://app.safe.global/home?safe=' + CHAIN_NAME + ':' + addr
        message.text('Created account: ').link(safe_link, safe_link)
        message.text("\n")

    if 'ApproveHash' in found_events_by_name:
        # print(found_events_by_name['ApproveHash'])
        addr = found_events_by_name['ApproveHash']['address']
        safe_link = 'https://app.safe.global/transactions/queue?safe=' + CHAIN_NAME + ':' + addr
        message.text('Complete approval here: ').link(safe_link, safe_link)
        message.text("\n")

    if 'AddedOwner' in found_events_by_name:
        owner = found_events_by_name['AddedOwner']['args']['owner']
        owner_etherscan_uri = 'https://sepolia.etherscan.io/address/' + owner
        message.text('Added owner ').link(owner, owner_etherscan_uri)
        message.text("\n")

    if 'LogPostMessage' in found_events_by_name:
        bbs = found_events_by_name['LogPostMessage']['address']
        bbs_etherscan_uri = 'https://sepolia.etherscan.io/address/' + bbs
        message.text('Posted message to ').link(bbs, bbs_etherscan_uri)
        message.text("\n")

    message.text('Transaction: ').link(txid, etherscan_uri)

    #print(bot_login[send_as_bot])
    print("\n")
    print(message.build_text())

    if not DRY_RUN:

        client = Client(bot_login[send_as_bot]['serviceEndpoint'])
        client.login(send_as_bot, bot_login[send_as_bot]['password'])

        post = client.app.bsky.feed.post.get(item['did'], item['rkey'])

        root_post_ref = models.create_strong_ref(post)

        result = client.send_post(
            text=message,
            reply_to=models.AppBskyFeedPost.ReplyRef(parent=root_post_ref, root=root_post_ref),
        )

        item['x_report_uri'] = result['uri']
        print("Posted reply: " + result['uri'])

    skeet_queue.updateStatus(at_uri, bot, "report", "completed", item)

    return


if __name__ == '__main__':

    if len(sys.argv) == 1:
        processQueue()
    else:
        if len(sys.argv) != 3:
            print("Usage: python send_tx.py <at_uri> <bot>")
            sys.exit(1)
        at_uri = sys.argv[1]
        bot = sys.argv[2]
        status = skeet_queue.status(at_uri, bot)
        if status == 'sent':
            handleItem(skeet_queue.readItem(at_uri, bot, status))
        else:
            if status is None:
                print("Not found in any queue.")
                sys.exit(2)
            if status != 'tx':
                print("Not currently queued for report. Status is " + status)
                sys.exit(3)
