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

import skeet_queue

skeet_queue.prepare()

CAR_CACHE = './cars'
DID_CACHE = './dids'
SKEET_CACHE = './skeets'
OUT_DIR = './out'

DID_DIRECTORY = 'https://plc.directory'
PARSER_CONFIG = 'parser_config.json'

# Returns whether or not the bot needs us to send it content of the skeet they're replying to.
# Hard-coding this for now. 
# Later we will probably add this information to the SkeetGateway contract.
# (It shouldn't change so it should be cacheable after you meet each bot for the first time.)
def isReplyParentContentNeededByBot(botName):
    try:
        with open(PARSER_CONFIG, mode="r") as cf:
            data = json.load(cf)
            bot_entry = data[botName]
            if 'metadata' in bot_entry and 'reply' in bot_entry['metadata']:
                return bool(bot_entry['metadata']['reply'])
        return False
    except:
        return False

def fetchAtURIForSkeetURL(skeet_url):

    if not os.path.exists(SKEET_CACHE):
        os.mkdir(SKEET_CACHE)

    skeet_file = SKEET_CACHE + '/' + hashlib.sha256(sys.argv[1].encode()).hexdigest()
    if os.path.exists(skeet_file):
        with open(skeet_file) as sf:
            at_addr = sf.read()
    else:
        with urllib.request.urlopen(skeet_url) as response:
            html = response.read()
            result = re.search('<link rel="alternate" href="(at://did:plc:.*?/app.bsky.feed.post/.*?)"', str(html))
            if result is None:
                raise Exception("Could not find the at:// link in the URL you provided. Maybe posts aren't shown unless you're logged in? Check the URL or pass an at:// URI instead.")

            at_addr = result.group(1) 

            with open(skeet_file, mode='w') as sf:
                sf.write(at_addr)
    print("Fetched at:// URI " + at_addr)
    return at_addr

def loadCar(did, rkey):

    if not os.path.exists(OUT_DIR):
        os.mkdir(OUT_DIR)

    if not os.path.exists(CAR_CACHE):
        os.mkdir(CAR_CACHE)

    if not os.path.exists(DID_CACHE):
        os.mkdir(DID_CACHE)

    did_file = DID_CACHE + '/' + hashlib.sha256(did.encode()).hexdigest()
    addresses = []
    if not os.path.exists(did_file):
        did_url = DID_DIRECTORY + '/' + did
        urllib.request.urlretrieve(did_url, did_file)

    endpoint = None
    with open(did_file, mode="r") as didf:
        data = json.load(didf)
        endpoint = data['service'][0]['serviceEndpoint']
        for vm in data['verificationMethod']: 
            addresses.append(vm['publicKeyMultibase'])

    # NB You have to get the right endpoint here, BSky service won't tell you about other people's PDSes.
    raw_filename = did + '-' + rkey
    car_file = CAR_CACHE + '/' + hashlib.sha256(raw_filename.encode()).hexdigest() + '.car'
    if not os.path.exists(car_file):
        car_url = endpoint + '/xrpc/com.atproto.sync.getRecord?did='+did+'&collection=app.bsky.feed.post&rkey='+rkey
        urllib.request.urlretrieve(car_url, car_file)

    with open(car_file, mode="rb") as cf:
        contents = cf.read()
        car_file = CAR.from_bytes(contents)
        return (car_file, addresses)

def recoverVParam(sighash, r, s, addresses):
    sig0 = KeyAPI.Signature(vrs=(0, int.from_bytes(r, byteorder='big'), int.from_bytes(s, byteorder='big')))
    pubkey0 = KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig0).to_compressed_bytes()

    sig1 = KeyAPI.Signature(vrs=(1, int.from_bytes(r, byteorder='big'), int.from_bytes(s, byteorder='big')))
    pubkey1 = KeyAPI.PublicKey.recover_from_msg_hash(sighash, sig1).to_compressed_bytes()

    for a in addresses:
        if decode(a)[2:] == pubkey0:
            return 27
        if decode(a)[2:] == pubkey1:
            return 28

    raise Exception("Could not find a v value matching the signature for a key in the did record")

def generatePayload(car_file, did, rkey, addresses, at_uri):

    # Output sorts keys alphabetically for compatibility with Forge json parsing.
    # The DID and rkey are only there to help keep track of things, they're not used by handleSkeet.
    output = {
        "atURI": at_uri,
        "botName": None,
        "botNameLength": None,
        "commitNode": None,
        "content": [],
        "did": did,
        "nodes": [],
        "nodeHints": [],
        "rkey": rkey,
        "sig": None,
    }

    target_content = None
    tip_node = None
    tree_nodes = []
    commit_node = None

    # This tells the verifier where to find the target data
    # 0 for the l node
    # i+1 for the e entries
    hints = []

    i = 0
    for cid in car_file.blocks:
        b = car_file.blocks[cid] 
        if 'sig' in b:
            commit_node = b
            signature = b['sig']
            del b['sig']
            # Reencode the commit node with the signature stripped
            # This will be needed for verification
            output['commitNode'] = "0x"+libipld.encode_dag_cbor(b).hex()
            v = recoverVParam(hashlib.sha256(libipld.encode_dag_cbor(b)).digest(), signature[0:32], signature[32:64], addresses)
            output['sig'] = "0x"+signature[0:64].hex() + hex(v)[2:]
        elif 'text' in b:
            target_content = b
            # print("Found text:")
            print(b)
            text = b['text']
            if not text.startswith('@'):
                raise Exception("Post should begin with @")
            message_bits = b['text'].split()
            bot_name = message_bits[0]
            # print("bot is " + bot_name)
            if bot_name[0:1] != '@':
                raise Exception("Bot name did not behing with @")
            bot_name = bot_name[1:]
            bot_name_length = len(bot_name)
            if bot_name_length == 0 or bot_name_length > 100:
                raise Exception("Bot name "+ bot_name + " is not the expected length")
            output['botName'] = bot_name
            output['botNameLength'] = bot_name_length

            # Currently we only use 1 entry for content, the node with the text in it.
            # However we use an array as in future we may want to support other entries
            # In particularly we may want to pass the skeet we are replying to
            output['content'] = ["0x"+libipld.encode_dag_cbor(b).hex()]

            if isReplyParentContentNeededByBot(bot_name):
                if not 'reply' in b or not 'parent' in b['reply']:
                    raise Exception("Bot " + bot_name + " needs the reply parent but none was found");
                parent_cid = b['reply']['parent']['cid']
                parent_uri = b['reply']['parent']['uri']
                (parent_did, parent_rkey) = atURIToDidAndRkey(parent_uri)
                (parent_car, ignore) = loadCar(parent_did, parent_rkey)
                parent_block = parent_car.blocks[parent_cid]
                if 'text' not in parent_car.blocks[parent_cid]:
                    raise Exception("Post we replied to does not appear to contain text")
                output['content'].append("0x"+libipld.encode_dag_cbor(parent_car.blocks[parent_cid]).hex())
                print("Added reply parent:")
                print(parent_block)

        elif i == len(car_file.blocks)-1:
            tip_node = b
        else:
            tree_nodes.append(b)
        i = i + 1

    # Provide the data starting at the tip of the tree (with the node that hashes the message)
    # Then work up to the root of the tree, so the final value hashes to its data field.
    tree_nodes.reverse()

    prove_me = hashlib.sha256(libipld.encode_dag_cbor(target_content)).hexdigest()

    is_found = False
    vidx = 0;
    for entry in tip_node['e']:
        if 'v' in entry:
            val = "0x"+entry['v'].hex()
            if val == "0x01711220" + prove_me:
                is_found = True
                output['nodes'].append("0x"+libipld.encode_dag_cbor(tip_node).hex());
                output['nodeHints'].append(vidx+1);
                prove_me = hashlib.sha256(libipld.encode_dag_cbor(tip_node)).hexdigest()
                break
        vidx = vidx + 1

    if not is_found:
        raise Exception("Could not find entry for data")

    # This assumes that the tree nodes are in the order we need for a proof.
    # This seems to be true in practice but is not guaranteed by the spec.
    j = 0
    for tree_node in tree_nodes:
        j = j + 1
        node_cbor = libipld.encode_dag_cbor(tree_node)
        tree_node_cid = hashlib.sha256(node_cbor).hexdigest()
        if tree_node['l'] is not None and "0x"+tree_node['l'].hex() == "0x01711220" + prove_me:
            prove_me = tree_node_cid
            output['nodeHints'].append(0); # 0 for the l node
            output['nodes'].append("0x"+node_cbor.hex());
        elif 'e' in tree_node:
            is_found_in_tree = False
            eidx = 0
            for tree_node_entry in tree_node['e']:
                if 't' in tree_node_entry and tree_node_entry['t'] is not None:
                    if "0x"+tree_node_entry['t'].hex() == "0x01711220" + prove_me:
                        prove_me = tree_node_cid
                        is_found_in_tree = True
                        output['nodeHints'].append(eidx+1); # e index + 1 for the t node
                        output['nodes'].append("0x"+node_cbor.hex());
                eidx = eidx + 1
            if not is_found_in_tree:
                print("Could not find cid: " + prove_me)
                print(repr(tree_node))
                print("Tree node I checked was: ")
                print(node_cbor.hex())
                print(str.find(node_cbor.hex(), prove_me))
                print("Full car file hex was: ")
                print(contents.hex())
                print(str.find(contents.hex(), prove_me))
                raise Exception("Could not find hash in tree entries")
        else:
            raise Exception("Could not find hash in tree node in l or t of one of the entries. Why did you pass me this thing.")

    if "0x"+commit_node['data'].hex() != "0x01711220" + prove_me:
        raise Exception("Sig node did not sign off on the expected root hash")

    return output

def atURIToDidAndRkey(at_uri):
    m = re.match(r'^at:\/\/(did:plc:.*?)/app\.bsky\.feed\.post\/(.*)$', at_uri)
    did = m.group(1)
    rkey = m.group(2)
    return (did, rkey)

def processQueuedPayloads():
    while True:
        item = skeet_queue.readNext("payload")
        if item is None:
            break

        print(item)
        at_uri = item['at_uri']
        bot = item['bot']

        try:
            (param_did, param_rkey) = atURIToDidAndRkey(at_uri)
            (car, addresses) = loadCar(param_did, param_rkey)
            item = generatePayload(car, param_did, param_rkey, addresses, at_uri)
            # item['payload'] = generatePayload(car, param_did, param_rkey, addresses)
            skeet_queue.updateStatus(at_uri, bot, "payload", "tx", item)
        except:
            skeet_queue.updateStatus(at_uri, bot, "payload", "payload_retry", item)

if __name__ == '__main__':

    if len(sys.argv) == 1 or (len(sys.argv) == 2 and sys.argv[1] == "queue"):
        processQueuedPayloads()
        sys.exit(0)

    if len(sys.argv) < 2:
        raise Exception("Usage: python prove_car.py <at://<did:plc:something>/app.bsky.feed.post/something>> ")

    at_uri = None

    # Secret feature: You can just past a bsky skeet URL in here and we'll get the at:// URL
    # If we get a post URL grab the at:// address 
    # It just scrapes the HTML so we don't have to futz with API keys so it will break one day without warning
    if sys.argv[1].startswith('https://bsky.app'):
        at_uri = fetchAtURIForSkeetURL(sys.argv[1])
    else:
        at_uri = sys.argv[1]

    (param_did, param_rkey) = atURIToDidAndRkey(at_uri)
    
    (car, addresses) = loadCar(param_did, param_rkey)
    output = generatePayload(car, param_did, param_rkey, addresses, at_uri)

    out_file = None
    if len(sys.argv) > 2:
        out_file = sys.argv[2]
    else:
        out_file = OUT_DIR + '/' + param_did + '-' + param_rkey + '.json'

    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=4, sort_keys=True)
        print("Output written to:")
        print(out_file)

