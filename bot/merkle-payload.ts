import {
  AtpAgent,
  AtpAgentOptions,
  ComAtprotoSyncGetRecord,
  CredentialSession,
} from "@atproto/api";
import { cborEncode } from "@atproto/common";
import { DidDocument } from "@atproto/identity";
import {
  cborToLexRecord,
  Commit,
  readCar,
  UnsignedCommit,
  verifyCommitSig,
} from "@atproto/repo";
import { CID } from "multiformats";
import assert from "node:assert";
import util from "node:util";

const isCommit3Lex = (c?: unknown): c is Commit | UnsignedCommit =>
  c != null &&
  typeof c == "object" &&
  c["data"] instanceof CID &&
  c["version"] === 3 &&
  typeof c["did"] == "string" &&
  typeof c["rev"] == "string";

const isSignedCommit3Lex = (c?: unknown): c is Commit =>
  isCommit3Lex(c) && c["sig"] instanceof Uint8Array && c["sig"].length === 64;

type PayloadData = {
  rootCid: CID;
  rootSig: Uint8Array;
  rootCbor: Uint8Array;
  targetKey: string;
  treeCids: CID[];
  treeCbors: Uint8Array[];
};

type PayloadSerialized = {
  rootCid: Uint8Array;
  rootSig: Uint8Array;
  rootCbor: Uint8Array;
  targetKey: Uint8Array;
  treeCids: Uint8Array[];
  treeCbors: Uint8Array[];
};

export const serializePayload = ({
  rootCid,
  rootSig,
  rootCbor,
  targetKey,
  treeCids,
  treeCbors,
}: PayloadData): PayloadSerialized => ({
  rootCid: rootCid.bytes,
  rootSig,
  rootCbor,
  targetKey: new TextEncoder().encode(targetKey),
  treeCids: treeCids.map((cid) => cid.bytes),
  treeCbors,
});

export const fetchPayloadData = async (
  verificationMethod: DidDocument["verificationMethod"][number],
  agentOpts: AtpAgent | AtpAgentOptions | CredentialSession,
  queryParams: ComAtprotoSyncGetRecord.QueryParams,
  callOpts?: ComAtprotoSyncGetRecord.CallOptions
): Promise<PayloadData> => {
  const agent =
    agentOpts instanceof AtpAgent ? agentOpts : new AtpAgent(agentOpts);

  const syncGetRecord = await agent.com.atproto.sync.getRecord(
    queryParams,
    callOpts
  );

  assert(
    syncGetRecord.success && syncGetRecord.data.length,
    util.inspect(syncGetRecord)
  );

  const { roots, blocks } = await readCar(syncGetRecord.data);

  assert(roots.length === 1, "Multi-root search unimplemented");

  const rootCid = roots[0];
  const rootBlock = blocks.get(rootCid);
  assert(rootBlock, "No root block");

  const { blockSig: rootSig, blockUnsigned: rootCbor } =
    await assertBlockSignature(verificationMethod, rootCid, rootBlock);

  const treeCids = blocks
    .cids()
    .filter((cid) => String(cid) !== String(rootCid));
  const treeCbors = treeCids.map((cid) => blocks.get(cid)!);
  const targetKey = `${queryParams.collection}/${queryParams.rkey}`;

  return {
    rootCid,
    rootSig,
    rootCbor,
    targetKey,
    treeCids,
    treeCbors,
  };
};

const assertBlockSignature = async (
  verificationMethod: DidDocument["verificationMethod"][number],
  blockCid: CID,
  signedBlock: Uint8Array
) => {
  assert(verificationMethod.publicKeyMultibase);

  assert(
    blockCid.multihash.digest ===
      (await crypto.subtle.digest("SHA-256", signedBlock)),
    "Mismatched block checksum"
  );

  const lexBlock = cborToLexRecord(signedBlock);
  assert(isSignedCommit3Lex(lexBlock), "Block is not a signed commit");

  const didKey = `did:key:${verificationMethod.publicKeyMultibase}`;
  assert(await verifyCommitSig(lexBlock, didKey), "Invalid block signature");

  const { sig: blockSig, ...lexBlockUnsigned } = lexBlock;

  return {
    blockSig,
    blockUnsigned: cborEncode(lexBlockUnsigned),
  };
};
