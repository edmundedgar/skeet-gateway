import web3
import os
import json

url = os.environ['SEPOLIA_RPC_URL']
w3 = web3.Web3(web3.HTTPProvider(url))

GATEWAY_ADDRESS = os.environ['SKEET_GATEWAY']

ABI_FILE = "../contract/out/SkeetGateway.sol/SkeetGateway.json"

with open(ABI_FILE) as f:
    d = json.load(f)

GATEWAY_ABI = d['abi']

gateway_contract = w3.eth.contract(address=GATEWAY_ADDRESS, abi=GATEWAY_ABI)

parser_config = {}

start_block = w3.eth.block_number
max_blocks = 100000
block_number = start_block
countLoaded = 0
while block_number > start_block - max_blocks:
    isFound = False
    block_number = block_number - 999 
    print("fetch from "+str(block_number))
    logs = gateway_contract.events.LogAddBot().get_logs(from_block=block_number, to_block = block_number+999)
    for log in logs:
       # AttributeDict({'args': AttributeDict({'parser': '0xA84F9FC27e849f636c18125c74358E003492f437', 'domain': 'unconsensus.com', 'subdomain': 'bbs'}), 'event': 'LogAddBot', 'logIndex': 125, 'transactionIndex': 101, 'transactionHash': HexBytes('0x215cdf64f66304cd3d8116ef85a8447eea814465003153970018ce117449fef1'), 'address ': '0xeB1Ef91e8658FE4b13Cc6A6d8E46c6Dcf5Aa63C1', 'blockHash': HexBytes('0x28353957873746df7ae5c56a9bd6143eb080bc4ead0330e6e37ede4894c1e6e8'), 'blockNumber': 7 351100})                       
        metadata_arg = log['args']['metadata'];
        metadata = None
        if metadata_arg == "":
            metadata = {}
        else:
            metadata = json.loads(metadata_arg)
        parser_config[log['args']['subdomain'] + '.' + log['args']['domain']] = {
            "parser": log['args']['parser'],
            "metadata": metadata
        }
        countLoaded = countLoaded + 1
        isFound = True
        with open('parser_config.json', 'w', encoding='utf-8') as f:
            json.dump(parser_config, f, ensure_ascii=False, indent=4)

    if isFound:
        print("loaded "+str(countLoaded))
