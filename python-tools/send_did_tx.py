import web3
from eth_account import Account
import os
import json
import time
import sys

import hashlib
import libipld
import binascii

import did_queue

from dotenv import load_dotenv

load_dotenv()

did_queue.prepare()

url = os.getenv('SEPOLIA_RPC_URL')
w3 = web3.Web3(web3.HTTPProvider(url))

SHADOW_DID_ADDRESS = os.getenv('SHADOW_DID')

ABI_FILE = "../contract/out/ShadowDIDPLCDirectory.sol/ShadowDIDPLCDirectory.json"
ACCOUNT = Account.from_key(os.getenv('PRIVATE_KEY'))

with open(ABI_FILE) as f:
    d = json.load(f)

SHADOW_DID_ABI = d['abi']

directory = w3.eth.contract(address=SHADOW_DID_ADDRESS, abi=SHADOW_DID_ABI)

def arrToBytesArr(arr):
    ret = []
    for item in arr:
        ret.append(w3.to_bytes(hexstr=item))
    return ret

def filterToNecessary(payload):
    # if we have an update already, we don't need the did
    # did_hex = binascii.hexlify(payload['did'].encode('utf-8'))
    did_bytes = payload['did'].encode('utf-8')
    start_at = 0
    i = 0
    is_genesis_recorded = False
    for op in payload['ops']:
        op_bytes = w3.to_bytes(hexstr=op)
        update_hash = hashlib.sha256(op_bytes).digest()
        ts = directory.functions.opRecordedTimestamp(did_bytes, update_hash).call()
        if ts > 0:
            is_genesis_recorded = True
            start_at = i + 1
        i = i + 1
    if len(payload['ops']) == 1:
        if is_genesis_recorded:
            return None, None
        else:
            start_at = start_at
    else:
        # For anything except the genesis update we need to supply the previous update
        start_at = start_at - 1

    payload['ops'] = payload['ops'][:start_at]
    payload['sigs'] = payload['sigs'][:start_at]
    payload['pubkeys'] = payload['pubkeys'][:start_at]
    payload['pubkeyIndexes'] = payload['pubkeyIndexes'][:start_at - 1]

    # New entries should have a did of 0x0
    if not is_genesis_recorded:
        did_bytes = w3.to_bytes(hexstr="0x0000000000000000000000000000000000000000000000000000000000000000")

    return (payload, did_bytes)

def sendTX(item):
    #payload = item['payload']
    payload, did_param = filterToNecessary(item)
    if payload is None:
        print("Nothing to do")
        return None, None

    print(payload)
    tx = None
    did_hex = binascii.hexlify(payload['did'].encode('utf-8'))
    print(did_param)
    #sys.exit(0)

    # w3.to_bytes(hexstr=payload['did']),
    #did_param = w3.to_bytes(hexstr="0x0000000000000000000000000000000000000000000000000000000000000000")
    #print(did_param)
    try:
        tx = directory.functions.registerUpdates(
            did_param,
            arrToBytesArr(payload['ops']),
            arrToBytesArr(payload['sigs']),
            arrToBytesArr(payload['pubkeys']),
            arrToBytesArr(payload['pubkeyIndexes']),
        ).build_transaction({
            "gas": 1000000,
            "from": ACCOUNT.address,
            "nonce": w3.eth.get_transaction_count(ACCOUNT.address),
        })
        #gas = w3.eth.estimateGas(tx)
        #print("gas is" + str(gas))
    except web3.exceptions.ContractLogicError as err:
        return (False, err.message)
    signed_tx = w3.eth.account.sign_transaction(tx, private_key=ACCOUNT.key).raw_transaction
    tx_hash = w3.eth.send_raw_transaction(signed_tx)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    return (True, receipt)

def diagnosisDetail(item):
    return {}
    commit_node = bytes.fromhex(item['commitNode'][2:])
    sighash = hashlib.sha256(commit_node).digest()
    balance = w3.eth.get_balance(signer_safe)
    code_len = len(w3.eth.get_code(signer_safe))
    is_deployed = False
    if code_len > 0:
        is_deployed = True
    return {
        'signer': signer,
        'signerSafe': signer_safe,
        'balance': balance,
        'isDeployed': is_deployed 
    }

def processQueue():
    while True:
        item = did_queue.readNext("tx")
        if item is None:
            break
        handleItem(item)

def handleItem(item):
    did = item['did']
    result, detail = sendTX(item)
    if not 'x_history' in item:
        item['x_history'] = [] 
    item['x_history'].append({
        str(time.time()): {
            "diagnosis": diagnosisDetail(item)
        }
    })
    if result:
        print("Completed: " + did)
        item['x_tx_hash'] = detail.transactionHash.to_0x_hex()
        did_queue.updateStatus(did, "tx", "report", item)
    else:
        if detail == 'execution reverted: Already handled':
            print("Was already completed: " + did)
            did_queue.updateStatus(did, "tx", "report", item)
        else:
            print("Failed, queued for retry: " + did)
            did_queue.updateStatus(did, "tx", "tx_retry", item)

if __name__ == '__main__':

    if len(sys.argv) == 1:
        processQueue()
    else:
        if len(sys.argv) != 3:
            print("Usage: python send_tx.py <at_uri> <bot>")
            sys.exit(1)
        did = sys.argv[1]
        status = did_queue.status(did)
        if status == 'tx':
            handleItem(did_queue.readItem(did, status))
        else:
            if status is None:
                print("Not found in any queue.")
                sys.exit(2)
            if status != 'tx':
                print("Not currently queued for tx send. Status is " + status)
                sys.exit(3)
