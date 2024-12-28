import web3
from eth_account import Account
import os
import json
import time
import sys

import skeet_queue

from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SEPOLIA_RPC_URL')
w3 = web3.Web3(web3.HTTPProvider(url))

GATEWAY_ADDRESS = os.getenv('SKEET_GATEWAY')

ABI_FILE = "../contract/out/SkeetGateway.sol/SkeetGateway.json"
ACCOUNT = Account.from_key(os.getenv('PRIVATE_KEY'))

with open(ABI_FILE) as f:
    d = json.load(f)

GATEWAY_ABI = d['abi']

gateway = w3.eth.contract(address=GATEWAY_ADDRESS, abi=GATEWAY_ABI)

def arrToBytesArr(arr):
    ret = []
    for item in arr:
        ret.append(w3.to_bytes(hexstr=item))
    return ret

def sendTX(item):
    #payload = item['payload']
    payload = item
    tx = None
    try:
        tx = gateway.functions.handleSkeet(
            arrToBytesArr(payload['content']),
            int(payload['botNameLength']),
            arrToBytesArr(payload['nodes']),
            payload['nodeHints'],
            w3.to_bytes(hexstr=payload['commitNode']),
            int(payload['v']),
            payload['r'],
            payload['s']
        ).build_transaction({
            "from": ACCOUNT.address,
            "nonce": w3.eth.get_transaction_count(ACCOUNT.address),
        })
        #gas = w3.eth.estimateGas(tx)
        #print("gas is" + str(gas))
    except web3.exceptions.ContractLogicError as err:
        #print(repr(err.message))
        print("tx prep failed")
        return (False, err.message)
    signed_tx = w3.eth.account.sign_transaction(tx, private_key=ACCOUNT.key).raw_transaction
    tx_hash = w3.eth.send_raw_transaction(signed_tx)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    return (True, receipt)

def processQueue():
    while True:
        item = skeet_queue.readNext("tx")
        if item is None:
            break
        handleItem(item)

def handleItem(item):
    at_uri = item['atURI']
    bot = item['botName']
    #print(at_uri)
    result, detail = sendTX(item)
    if result:
        item['receipt'] = detail
        skeet_queue.updateStatus(at_uri, bot, "tx", "completed", item)
    else:
        if not 'x_history' in item:
            item['x_history'] = [] 
        item['x_history'].append({str(time.time()): detail}) 
        if detail == 'execution reverted: Already handled':
            skeet_queue.updateStatus(at_uri, bot, "tx", "completed", item)
        else:
            skeet_queue.updateStatus(at_uri, bot, "tx", "tx_retry", item)

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
        if status == 'tx':
            handleItem(skeet_queue.readItem(at_uri, bot, status))
        else:
            if status is None:
                print("Not found in any queue.")
                sys.exit(2)
            if status != 'tx':
                print("Not currently queued for tx send. Status is " + status)
                sys.exit(3)
