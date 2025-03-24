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

load_dotenv(dotenv_path='../contract/.env')

skeet_queue.prepare()

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
    print("handle item" + at_uri)
    bot = item['botName']
    txid = item['x_tx_hash']
    etherscan_uri = 'https://sepolia.etherscan.io/tx/' + txid

    send_as_bot = default_bot
    if bot in bot_login:
        send_as_bot = bot
    
    message = client_utils.TextBuilder().text('Transaction sent: ').link(etherscan_uri, etherscan_uri)

    if bot == 'bbs.unconsensus.com':
        message = client_utils.TextBuilder().text('Message posted: ').link(etherscan_uri, etherscan_uri)

    print(bot_login[send_as_bot])

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
    #else:
    #    print("Failed, queued for retry: " + at_uri + " (" + bot + ")")
    #    skeet_queue.updateStatus(at_uri, bot, "report", "report_retry", item)

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
