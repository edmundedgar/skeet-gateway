import sys
import binascii

arg = sys.argv[1]

if arg[:8] == 'did:plc:':
    print(str(binascii.hexlify(arg.encode('utf-8'))))
else:
    print(str(binascii.unhexlify(arg)))
