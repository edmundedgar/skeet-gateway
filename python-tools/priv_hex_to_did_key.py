import sys
import os
from eth_keys import KeyAPI, keys

import base58

if __name__ == '__main__':

    if len(sys.argv) < 2:
        raise Exception("Usage: python did_tool.py <pk file>")

    key_file = sys.argv[1]

    key_hex = None
    with open(key_file) as f:
        key_hex = f.read().rstrip()

    if not key_hex[0:2] == "0x":
        raise Exception("Key should being with 0x")

    if not len(key_hex) == 66:
        raise Exception("Key should be 66 chars long (0x + 32 bytes)")

    pk = keys.PrivateKey(bytes.fromhex(key_hex[2:]))
    pub = pk.public_key.to_compressed_bytes()

    prepend = bytes.fromhex("e701");
    pub_bytes = bytearray(prepend)
    pub_bytes.extend(pub)
    b58encoded = base58.b58encode(pub_bytes)

    did_key = "did:key:z" + str(b58encoded.decode('utf-8'))
    print(did_key)

