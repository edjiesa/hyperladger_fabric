#!/usr/bin/env python3
import sys, json, base64, hashlib

data = json.load(sys.stdin)
msp = data["data"]["data"][0]["payload"]["data"]["config"]["channel_group"]["groups"]["Application"]["groups"]["Org1MSP"]["values"]["MSP"]["value"]["config"]
root_b64 = msp["root_certs"][0]
decoded = base64.b64decode(root_b64)
print("MD5 of root_cert in genesis:", hashlib.md5(decoded).hexdigest())
