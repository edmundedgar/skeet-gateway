#1/bin/bash -x

python fetch_skeets.py 
python prepare_payload.py 
python send_tx.py 

python find_active_dids.py 
python watch_did_update.py 
python prepare_did_update.py 
python send_did_tx.py 
