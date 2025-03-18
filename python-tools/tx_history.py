import web3
from eth_account import Account
import os
import json
import time
import sys

import hashlib

import skeet_queue

from dotenv import load_dotenv

load_dotenv(dotenv_path='../contracts/.env')

skeet_queue.prepare()

url = os.getenv('SEPOLIA_RPC_URL')
w3 = web3.Web3(web3.HTTPProvider(url))

GATEWAY_ADDRESS = os.getenv('SKEET_GATEWAY')
DEPLOYMENT_BLOCK = os.getenv('DEPLOYMENT_BLOCK')

ABI_FILE = "../contract/out/SkeetGateway.sol/SkeetGateway.json"
ACCOUNT = Account.from_key(os.getenv('PRIVATE_KEY'))

with open(ABI_FILE) as f:
    d = json.load(f)

GATEWAY_ABI = d['abi']

gateway = w3.eth.contract(address=GATEWAY_ADDRESS, abi=GATEWAY_ABI)

tx_hist = {
    "lastBlock": DEPLOYMENT_BLOCK,
    "txByContentHash": {}
}

TX_FILE = "tx_hist.json"

if __name__ == '__main__':

    if os.path.exists(TX_FILE):
        with open(TX_FILE) as f:
            tx_hist = json.load(f) 

    latest_block = w3.eth.block_number
    block_number = int(tx_hist['lastBlock'])
    countLoaded = 0
    while block_number < latest_block:
        from_block = block_number
        to_block = block_number + 999
        if to_block > latest_block:
            to_block = latest_block
        block_number = to_block

        isFound = False
        print("fetch range "+str(from_block) + "-" + str(to_block))
        logs = gateway.events.LogExecutePayload().get_logs(from_block=from_block, to_block = to_block)
        for log in logs:
            content_hash = "0x"+log['args']['contentHash'].hex()
            to = log['args']['to']
            data = "0x"+log['args']['data'].hex()
            value = log['args']['value']
            txid = log['transactionHash'].to_0x_hex()
            tx_hist["txByContentHash"][content_hash] = {
                "txid": txid,
                "to": to,
                "data": data,
                "value": value
            }
            countLoaded = countLoaded + 1
            isFound = True

        if isFound:
            print("loaded "+str(countLoaded))

    tx_hist['lastBlock'] = block_number
    with open(TX_FILE, 'w', encoding='utf-8') as f:
        json.dump(tx_hist, f, ensure_ascii=False, indent=4)
