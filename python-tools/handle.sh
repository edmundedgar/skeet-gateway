#!/bin/bash -x

# Only need to run this after deploying a bot
# python load_bots.py

python fetch_skeets.py 
python prepare_payload.py 
python send_tx.py 
python report_tx.py

python find_active_dids.py 
python watch_did_update.py 
python prepare_did_update.py 
python send_did_tx.py
