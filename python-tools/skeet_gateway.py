import web3
from eth_account import Account
import os
import json
import time
import sys

import hashlib

import skeet_queue

from dotenv import load_dotenv

load_dotenv(dotenv_path='../contract/.env')

skeet_queue.prepare()

url = os.getenv('SEPOLIA_RPC_URL')
w3 = web3.Web3(web3.HTTPProvider(url))

GATEWAY_ADDRESS = os.getenv('SKEET_GATEWAY')

ABI_FILE = "../contract/out/SkeetGateway.sol/SkeetGateway.json"
ACCOUNT = Account.from_key(os.getenv('PRIVATE_KEY'))

with open(ABI_FILE) as f:
    d = json.load(f)

GATEWAY_ABI = d['abi']

gateway = w3.eth.contract(address=GATEWAY_ADDRESS, abi=GATEWAY_ABI)


def selectedSafeAddress(did, addr):
    did_bytes = did.encode('utf-8')
    print(did_bytes)
    print(addr)
    return gateway.functions.selectedSafeAddress(did_bytes, addr).call()

def arrToBytesArr(arr):
    ret = []
    for item in arr:
        ret.append(w3.to_bytes(hexstr=item))
    return ret


# TODO: These are copied from send_tx.py
# Remove them from send_tx.py and import them from here instead

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
            w3.to_bytes(hexstr=payload['sig']),
        ).build_transaction({
            "from": ACCOUNT.address,
            "nonce": w3.eth.get_transaction_count(ACCOUNT.address),
        })
        gas = w3.eth.estimate_gas(tx)
        print("Gas estimate: " + str(gas))
    except (web3.exceptions.ContractLogicError, web3.exceptions.Web3RPCError) as err:
        return (False, None, err)
    signed_tx = w3.eth.account.sign_transaction(tx, private_key=ACCOUNT.key).raw_transaction
    tx_hash = w3.eth.send_raw_transaction(signed_tx)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    return (True, receipt, None)

def diagnosisDetail(item):
    commit_node = bytes.fromhex(item['commitNode'][2:])
    sighash = hashlib.sha256(commit_node).digest()
    signer = gateway.functions.predictSignerAddressFromSig(sighash, item['sig']).call()
    did_bytes = item['did'].encode('utf-8')
    signer_safe = gateway.functions.predictSafeAddressFromDidAndSig(did_bytes, sighash, item['sig'], 0).call()
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
