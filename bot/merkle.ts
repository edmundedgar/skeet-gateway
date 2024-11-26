import { cborEncode } from "@atproto/common";
import { verifySignature } from "@atproto/crypto";
import type { RepoRecord } from "@atproto/lexicon";
import {
  type BlockMap,
  cborToLexRecord,
  Commit,
  formatDataKey,
  nodeDataDef,
  parseDataKey,
  readCarWithRoot,
  RecordPath,
  schema,
  UnsignedCommit,
} from "@atproto/repo";
import type { CID } from "multiformats/cid";
import assert from "node:assert";
import { VerificationMaterial } from "./did-document.js";

// TODO:
// - validate order
// - validate depth
// - more efficient walk?

const debug = console.info;

const td = new TextDecoder();

const parseNodeData = (r: RepoRecord) => nodeDataDef.schema.parse(r);
const parseCommitData = (r: RepoRecord) => schema.commit.parse(r);

const compareBytes = (a: ArrayBufferLike, b: ArrayBufferLike) => {
  const aStr = Buffer.from(a).toString("hex");
  const bStr = Buffer.from(b).toString("hex");
  const compare = aStr === bStr;
  if (!compare) debug(aStr, "!=", bStr);
  return compare;
};

export async function validateInclusion(
  verificationMaterial: VerificationMaterial,
  target: RecordPath,
  { root, blocks }: Awaited<ReturnType<typeof readCarWithRoot>>
): Promise<{ cid: CID; record: RepoRecord }> {
  debug("Validating inclusion", target);
  assert(root, "No root commit identified");

  const { nodeRef } = await validateCommit(
    verificationMaterial,
    root,
    blocks.get(root)!
  );

  const targetCid = await walkTree(target, nodeRef, blocks);

  return { cid: targetCid, record: cborToLexRecord(blocks.get(targetCid)!) };
}

async function validateRecord(
  recordKey: string,
  v: CID,
  blocks: BlockMap
): Promise<CID> {
  debug("Validating record", v);

  const { collection } = parseDataKey(recordKey);

  const recordCbor = blocks.get(v);
  assert(recordCbor, "No record for cid");
  assert(
    compareBytes(
      v.multihash.digest,
      await crypto.subtle.digest("SHA-256", recordCbor)
    ),
    "Invalid target record hash"
  );
  debug("Valid record hash");

  const record = cborToLexRecord(recordCbor);

  assert(
    collection === record["$type"],
    "Record type does not match expected collection"
  );

  return v;
}

async function walkTreeDeep(
  targetKey: string,
  nodeId: CID,
  blocks: BlockMap,
  walkStack: number
): Promise<undefined | CID> {
  const nodeCbor = blocks.get(nodeId);
  assert(nodeCbor, `${walkStack} No record for ${nodeId}`);
  debug(walkStack, "walking", nodeId);

  assert(
    walkStack < blocks.size,
    "walkTreeDeep recursion exceeded number of nodes (tree cycle)"
  );

  const nodeSha = await crypto.subtle.digest("SHA-256", nodeCbor);
  assert(
    compareBytes(nodeSha, nodeId.multihash.digest),
    `${walkStack} Failed to verify node hash`
  );

  const node = parseNodeData(cborToLexRecord(nodeCbor));

  const walk: ReturnType<typeof walkTreeDeep>[] = new Array();

  if (node.l) {
    if (blocks.has(node.l)) {
      debug(walkStack, "pushing left path", node.l);
      walk.push(walkTreeDeep(targetKey, node.l, blocks, walkStack + 1));
    } else {
      // debug(walkStack, "unincluded left path", node.l);
    }
  }

  // entry keys are compressed. each entry's `k` removes `p` bytes of prefix
  // matching the previous entry's `k`
  let prevKey = new Uint8Array();
  for (const e of node.e) {
    const { p, k, v, t } = e;
    const keyBytes = Uint8Array.from([...prevKey.slice(0, p), ...k]);
    prevKey = keyBytes;
    const key = td.decode(keyBytes);

    if (t) {
      if (blocks.has(t)) {
        debug(walkStack, "pushing right path", { k: key, v, t });
        walk.push(walkTreeDeep(targetKey, t, blocks, walkStack + 1));
      } else {
        // debug(walkStack, "unincluded right path", t);
      }
    }

    if (targetKey === key) {
      debug(walkStack, "matching entry", { k: key, v, t });
      walk.push(validateRecord(targetKey, v, blocks));
    }
  }

  return Promise.all(walk).then((wr) => {
    const [oneResult, ...extra] = wr.filter((r) => r != null);
    assert(!extra.length, `${walkStack} Should not find more than one item`);
    debug(walkStack, "found target", oneResult);
    return oneResult;
  });
}

export async function walkTree(
  target: RecordPath,
  start: CID,
  blocks: BlockMap
): Promise<CID> {
  const walkResult = await walkTreeDeep(
    formatDataKey(target.collection, target.rkey),
    start,
    blocks,
    0
  );
  assert(walkResult, "Target record not included in tree");
  return walkResult;
}

export async function validateCommit(
  { publicKeyMultibase }: VerificationMaterial,
  signedCommitCid: CID,
  signedCommitCbor: Uint8Array
): Promise<{
  sig: Uint8Array;
  commit: Uint8Array;
  nodeRef: CID;
}> {
  const didKey = `did:key:${publicKeyMultibase}`;

  assert(
    compareBytes(
      signedCommitCid.multihash.digest,
      await crypto.subtle.digest("SHA-256", signedCommitCbor)
    ),
    "Commit hash invalid"
  );
  debug("Commit hash valid");

  const { sig, ...unsignedCommit } = parseCommitData(
    cborToLexRecord(signedCommitCbor)
  );

  debug("Validating commit", { didKey, sig: Buffer.from(sig).toString("hex") });

  assert(
    await validateCommitSignature(didKey, unsignedCommit, sig),
    "Commit signature invalid"
  );
  debug("Commit signature valid");

  return {
    sig,
    commit: cborEncode(unsignedCommit),
    nodeRef: unsignedCommit.data,
  };
}

export async function validateCommitSignature(
  didKey: string,
  { sig, ...unsignedCommit }: Commit
): Promise<boolean>;
export async function validateCommitSignature(
  didKey: string,
  unsignedCommit: UnsignedCommit,
  sig: Uint8Array
): Promise<boolean>;
export async function validateCommitSignature(
  didKey: string,
  { sig: commitSig, ...unsignedCommit }: Commit | UnsignedCommit,
  sig = commitSig
): Promise<boolean> {
  assert(sig, "No signature provided");
  return verifySignature(didKey, cborEncode(unsignedCommit), sig);
}
