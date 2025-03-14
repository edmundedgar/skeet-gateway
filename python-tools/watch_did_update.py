import os
from dotenv import load_dotenv
import psycopg

import time

import json
import hashlib
import libipld

import did_queue


load_dotenv(dotenv_path='../.plc_env')

PLC_MIRROR_HOST = os.getenv('PLC_MIRROR_HOST')
PLC_MIRROR_PORT = os.getenv('PLC_MIRROR_PORT')
PLC_MIRROR_DB = os.getenv('PLC_MIRROR_DB')
PLC_MIRROR_USER = os.getenv('PLC_MIRROR_USER')
PLC_MIRROR_PWD = os.getenv('PLC_MIRROR_PWD')

# Watch contracts for interest in DID
# If found, add to db subscription list
#  SkeetGateway.LogHandleAccount has did

did_queue.prepare()

# Watch subscription list for unpublished changes
# If found add entry cid to sighash

# did
# first_seen_ts

# shadow_update
#  cid
#  sighash
#  sent_ts

# Watch contracts for shadowed changes
# If found, mark done in db

# Connect to an existing database
with psycopg.connect(host=PLC_MIRROR_HOST, port=PLC_MIRROR_PORT, dbname=PLC_MIRROR_DB, user=PLC_MIRROR_USER, password=PLC_MIRROR_PWD) as conn:

    # exists_sql = "SELECT count(*) as cnt FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscriptions'"

    # TODO: Get this list from the contract logs
    # Make sure each did gets logged the first time with a timestamp or block that we can keep track of
    dids = ['did:plc:pyzlzqt6b2nyrha7smfry6rv', 'did:plc:mtq3e4mgt7wyjhhaniezej67']

    create_sql = """    
        CREATE TABLE if not exists subscribed_dids (
          did text,
          sent_ts bigint
        );

        CREATE TABLE if not exists shadow_updates (
          cid text UNIQUE NOT NULL,
          sighash VARCHAR (255) UNIQUE NOT NULL,
          sent_ts bigint NOT NULL
        );
    """

    missing_sql = """
        select s.did, p.cid, p.operation
            from plc_log_entries p 
                inner join subscribed_dids s 
                on p.did=s.did 
            left outer join 
                shadow_updates u 
                on p.cid=u.cid 
            where u.cid is null;
    """

    # create index cid on public.plc_log_entries using btree(cid)

    # Open a cursor to perform database operations
    with conn.cursor() as cur:

        print("create")
        cur.execute(create_sql)

        for did in dids:
            print("check did" + did)
            cur.execute('SELECT count(*) FROM subscribed_dids where did = %s', (did,))
            num_arr = cur.fetchone()
            num = num_arr[0]
            if num == 0:
                print("insert did" + did)
                cur.execute('insert into subscribed_dids(did, sent_ts) values (%s,%s)', (did,int(time.time()),))
        conn.commit()

        print("check missing")
        cur.execute(missing_sql)
        insert_me = []
        for record in cur:
            missing_did = record[0]
            missing_cid = record[1]
            missing_op = record[2]

            signed_op = missing_op.copy()
            del signed_op["sig"]
            signable_cbor = libipld.encode_dag_cbor(signed_op)
            sighash = "0x" + hashlib.sha256(signable_cbor).hexdigest()
            # insert_me.append((missing_cid, sighash ,int(time.time()),))
            insert_me.append((missing_cid, sighash, 0,))
            # print(sig_hash)
            print("read record")

        for me in insert_me:
            print("insert cid")
            cur.execute('insert into shadow_updates(cid, sighash, sent_ts) values (%s,%s,%s)', me)

        conn.commit()

        print("get diss")
        cur.execute('SELECT distinct(did) from shadow_updates u inner join plc_log_entries p on u.cid=p.cid where u.sent_ts = %s', (0,))
        for record in cur:
            did = record[0]
            status = did_queue.status(did)
            if status is None:
                did_queue.queueForPayload(did)
                print("Queued: "+did)
