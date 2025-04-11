# This is a script to prepare the payload used by SkeetGateway.handleSkeet()

# It outputs a json file with what it found under out/.

# It assumes certain things about the result we get from the PDS (especially the record order) that aren't guaranteed by the spec. 
# If these are wrong it will error out.

# The records it fetches from various APIs are cached to disk to avoid hitting the same API endpoint repeatedly.
# The data you get when making a fresh request may be different to what is saved to disk, although a payload generated from a previous cached request will still be valid.

from atproto import CAR, Client
import urllib.request
import sys
import os
import re
import json
import hashlib
import libipld
from multibase import encode, decode
from eth_keys import KeyAPI
import base64
import argparse

import did_queue

did_queue.prepare()

DID_CACHE = './dids'
PLC_CACHE = './plcs'
SKEET_CACHE = './skeets'
OUT_DIR = './out'

DID_DIRECTORY = 'https://plc.directory'

# https://plc.directory/did:plc:pyzlzqt6b2nyrha7smfry6rv/log/audit


def pubkeyCompressedAndUncompressed(pubkey):
    # return the uncompressed pubkey
    # but with the 02 or 03 for the compressed pubkey prepended on the front
    # that way we can get whichever we need as a calldata slice
    uncompressed = str(pubkey)[2:] # trim the 0x
    compressed = pubkey.to_compressed_bytes().hex() # no leading 0x
    return "0x" + compressed[0:2] + uncompressed

def recoverPubkeyAndVParam(sighash, r, s, addresses):
    sig0 = KeyAPI.Signature(vrs=(0, int.from_bytes(r, byteorder='big'), int.from_bytes(s, byteorder='big')))
    pubkey0 = KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig0)

    #print(repr(pubkey0))
    #print(pubkey0.to_compressed_bytes().hex())
    #print("pubkey0")
    #print(KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig0))
    #print(pubkey0.hex())
    #print(len(pubkey0))
    #print(KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig0).to_checksum_address())

    sig1 = KeyAPI.Signature(vrs=(1, int.from_bytes(r, byteorder='big'), int.from_bytes(s, byteorder='big')))
    pubkey1 = KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig1)
    #print(repr(pubkey1))
    #print("pubkey0")
    #print(KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig1))
    #print(pubkey1.hex())
    #print("pubkey1")
    #print(KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig1).to_checksum_address())

    addr_idx = 0
    for a in addresses:
        #print("a")
        #print(a.hex())
        #print(pubkey0.hex())
        #print(pubkey1.hex())
        if a == pubkey0.to_compressed_bytes():
            #return pubkeyCompressedAndUncompressed(pubkey0), 27, addr_idx
            return str(pubkey0), 27, addr_idx
        if a == pubkey1.to_compressed_bytes():
            #return pubkeyCompressedAndUncompressed(pubkey1), 28, addr_idx
            return str(pubkey1), 28, addr_idx
        addr_idx = addr_idx + 1
        #if decode(a)[2:] == pubkey0:
        #    return 27
        #if decode(a)[2:] == pubkey1:
        #    return 28

    raise Exception("Could not find a v value matching the signature for a key in the did record")

def loadHistory(did):

    if not os.path.exists(OUT_DIR):
        os.mkdir(OUT_DIR)

    if not os.path.exists(PLC_CACHE):
        os.mkdir(PLC_CACHE)

    if not os.path.exists(DID_CACHE):
        os.mkdir(DID_CACHE)

    did_file = DID_CACHE + '/' + hashlib.sha256(did.encode()).hexdigest()
    addresses = []
    if not os.path.exists(did_file):
        did_url = DID_DIRECTORY + '/' + did
        urllib.request.urlretrieve(did_url, did_file)

    #with open(did_file, mode="r") as didf:
    #    data = json.load(didf)
    #    for vm in data['verificationMethod']: 
    #        addresses.append(vm['publicKeyMultibase'])

    # NB You have to get the right endpoint here, BSky service won't tell you about other people's PDSes.
    plc_file = PLC_CACHE + '/' + hashlib.sha256(did.encode()).hexdigest() + '.plc'
    if not os.path.exists(plc_file):
        plc_url = DID_DIRECTORY + '/' + did + '/log/audit'
        urllib.request.urlretrieve(plc_url, plc_file)

    with open(plc_file, mode="rb") as cf:
        return json.load(cf)

def generatePayload(did, did_history):

    # Output sorts keys alphabetically for compatibility with Forge json parsing.
    # The DID and rkey are only there to help keep track of things, they're not used by handleSkeet.
    output = {
        "did": did,
        "ops": [],
        "pubkeyIndexes": [],
        "pubkeys": [],
        "sigs": []
    }

    # These aren't needed for normal operation but we can use them to create test vectors for our various encoding needs
    test_vectors = {
        "base64URLSig": [],
        "cid": [],
        "rotationKeys": []
    }

    active_rotation_keys = []
    next_rotation_keys = []

    is_first = True
    last_signed_op_hash = None
    for entry in did_history:
        if entry['nullified']:
            print("skipping nullfiied entry")
            continue
        #print(entry)
        # {"did":"did:plc:pyzlzqt6b2nyrha7smfry6rv","operation":{"sig":"qI31xjIX949GGbwWqsSGU5FZLVrfbv9N_695lr61w_MYgfsJE_k-oG8SQVLjWk20esEdhA55pFUCeQEJ7hZGDw","prev":"bafyreibufnyztvxkqnth2fjj4sggvhncw4rbhrdxjttejvboc3s6j72yyy","type":"plc_operation","services":{"atproto_pds":{"type":"AtprotoPersonalDataServer","endpoint":"https://lionsmane.us-east.host.bsky.network"}},"alsoKnownAs":["at://goat.navy"],"rotationKeys":["did:key:zQ3shhCGUqDKjStzuDxPkTxN6ujddP4RkEKJJouJGRRkaLGbg","did:key:zQ3shpKnbdPx3g3CmPf5cRVTPe1HtSwVn5ish3wSnDPQCbLJK"],"verificationMethods":{"atproto":"did:key:zQ3shRQWmWxEtxRa317rpYnVo7nWxYAsDS4mBwdDLgLfkkDtR"}},"cid":"bafyreifbilrkm7ktlamiqslrjq33bbnhs6pj4pstasnpg4ly5mimmjxjam","nullified":false,"createdAt":"2024-09-08T09:30:26.927Z"}]
        op = entry["operation"]
        cbor_bytes = libipld.encode_dag_cbor(op)
        sig_in_base64_url = op["sig"]

        # apparently the base64 lib gets mad about too little padding at the end, but doesn't care if you give it too much
        sig = base64.urlsafe_b64decode(op["sig"] + '===') 
        r = sig[0:32]
        s = sig[32:64]
        test_vectors["base64URLSig"].append({
            "encoded": op["sig"],
            "decoded": "0x"+sig.hex()
        })
        
        # print(op)
        # only really needed for the last item
        entry_verification_key = None
        if 'verificationMethods' in op and 'atproto' in op['verificationMethods']:
            ver_key = op["verificationMethods"]["atproto"]
            ver_key_base58btc = ver_key.lstrip("did:key:")
            entry_verification_key = decode(ver_key_base58btc)[2:]

        next_rotation_keys = []
        for did_key in op["rotationKeys"]:
            did_key_base58btc = did_key.lstrip("did:key:")
            did_key_decoded = decode(did_key_base58btc)[2:]
            next_rotation_keys.append(did_key_decoded)
            test_vectors['rotationKeys'].append({
                "encoded": did_key,
                "decoded": "0x"+did_key_decoded.hex()
            })
                

        # For the genesis operation, we sign with our own rotation keys ¯\_(ツ)_/¯
        if is_first:
            active_rotation_keys = next_rotation_keys

        signed_op = op.copy()
        del signed_op["sig"]
        signable_cbor = libipld.encode_dag_cbor(signed_op)

        # Find the index where the sig starts for when we need to reconstruct the signed 

        # There will be 2 differences to the cbor-encoded version with the signature stripped.
        # Firstly it will be a mapping with 1 entry fewer, so the first byte will differ by 1.
        # Secondly the "sig: encoded text" will be different, which will be:
        #  - Text header + sig
        #  - Text header for however much text + the text
        # This will be a 
        mapping_byte_signed = int.from_bytes(cbor_bytes[0:1], byteorder='big')
        mapping_byte_signable = int.from_bytes(signable_cbor[0:1], byteorder='big')
        if mapping_byte_signed != mapping_byte_signable + 1:
            raise Exception("Unexpected initial cbor mapping entry count")

        # Get the index where the sig field will be added
        # This will always be 1 unless they add a key that sorts before "sig" (ie 3 letters or less)
        sig_bytes = b''.join([libipld.encode_dag_cbor("sig"), libipld.encode_dag_cbor(sig_in_base64_url)])
        sig_start_idx = cbor_bytes.find(sig_bytes)

        # Sanity-check this by putting the original cbor back together
        recreated_cbor = b''.join([cbor_bytes[0:1], signable_cbor[1:sig_start_idx], sig_bytes, signable_cbor[sig_start_idx:]])
        if recreated_cbor != cbor_bytes:
            raise Exception("Something went wrong with our assumptions about encoding the sig in cbor")

        sig_hash = hashlib.sha256(signable_cbor).digest()
        #print("made sig_hash")
        #print(sig_hash.hex())

        pubkey_str, v, rotation_key_idx = recoverPubkeyAndVParam(sig_hash, r, s, active_rotation_keys)
        sig = b''.join([r, s, v.to_bytes(1, byteorder="big")])
        #print("rs")
        #print(r.hex());
        #print(s.hex());

        # TODO: In solidity, see if it's easier to pass the sig then base64-url-encode it to recreate the signed cbor
        # ...or pass the full signed cbor and base64-url-decode it to make the signature

        output["ops"].append("0x"+signable_cbor.hex())
        output["pubkeyIndexes"].append(rotation_key_idx)
        output["pubkeys"].append(pubkey_str)
        output["sigs"].append("0x"+sig.hex())
            
        #print(cbor)
        #print(cid_hash)

        if is_first:
            if op["prev"] is not None:
                #print(op["prev"])
                raise Exception("Genesis operation had a prev set which is weird")
        else:
            if last_signed_op_hash != decode(op["prev"])[4:]:
                raise Exception("prev does not match hash of previous entry")
            test_vectors["cid"].append({
                "encoded": op["prev"],
                "decoded": "0x"+last_signed_op_hash.hex()    
            })


        last_signed_op_hash = hashlib.sha256(cbor_bytes).digest()

        is_first = False
        active_rotation_keys = next_rotation_keys


    # Shift the pubkeys and indexes up 1 as we sign with the pubkey from the previous entry
    output['pubkeys'] = output['pubkeys'][1:]
    output['pubkeyIndexes'] = output['pubkeyIndexes'][1:]

    validator_pubkey = KeyAPI.PublicKey.from_compressed_bytes(entry_verification_key)
    output['pubkeys'].append(str(validator_pubkey))
    # print("address:")
    # print(validator_pubkey.to_checksum_address())

    return output, test_vectors

def processQueuedPayloads():
    while True:
        item = did_queue.readNext("payload")
        if item is None:
            break

        did = item['did']

        # TODO: Check this picks up from the right place
        did_history = loadHistory(did)

        print(did)
        print(did_history)
        item, test_vectors = generatePayload(did, did_history)
        print(item)

        # item['payload'] = generatePayload(car, param_did, param_rkey, addresses)
        did_queue.updateStatus(did, "payload", "tx", item)

if __name__ == '__main__':

    if len(sys.argv) == 1 or (len(sys.argv) == 2 and sys.argv[1] == "queue"):
        processQueuedPayloads()
        sys.exit(0)

    parser = argparse.ArgumentParser()
    parser.add_argument("--history", help="history file to load direct from (instead of the directory)")
    parser.add_argument("--did", required=True, help="did to load")
    parser.add_argument("--out", help="name of file to output")
    args = parser.parse_args()

    at_uri = None
    param_did = args.did
    
    did_history = []
    if args.history is not None:
        with open(args.history, mode="rb") as cf:
            did_history = json.load(cf)
    else:
        did_history = loadHistory(param_did)

    output, test_vectors = generatePayload(param_did, did_history)

    out_file = None
    if args.out is not None:
        out_file = args.out
    else:
        out_file = OUT_DIR + '/' + param_did + '.json'

    test_out_file = OUT_DIR + '/test-' + param_did + '.json'

    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=4, sort_keys=True)
        print("Output written to:")
        print(out_file)

    with open(test_out_file, 'w', encoding='utf-8') as f:
        json.dump(test_vectors, f, indent=4, sort_keys=True)
        print("Test vector output written to:")
        print(test_out_file)
