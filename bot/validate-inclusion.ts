import { Agent } from "@atproto/api";
import { DidDocument, DidResolver } from "@atproto/identity";
import { RepoRecord } from "@atproto/lexicon";
import {
  BlockMap,
  cborToLexRecord,
  nodeDataDef,
  readCar,
  schema,
  verifyCommitSig,
} from "@atproto/repo";
import { CID } from "multiformats";
import assert from "node:assert";

// TODO:
// - validate order
// - validate depth
// - don't return before whole tree is valid
// - cycle detection
// - more efficient walk?
// - don't walk all paths in parallel?

const [
  atUriArg = "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3laydu3mgac2v",
  agentArg = "https://bsky.network",
  plcUrl = "https://plc.directory",
] = process.argv.slice(2);

const [_, did, collection, rkey] = atUriArg.match(
  /^at:\/\/(did:[\w\d]*:[\w\d]*)\/([\w\d\.]*)\/([\w\d]*)/
);

const debug = console.log;

const td = new TextDecoder();

const parseNodeData = (r: RepoRecord) => nodeDataDef.schema.parse(r);
const parseCommitData = (r: RepoRecord) => schema.commit.parse(r);

export async function validateInclusion(
  verificationMethod: DidDocument["verificationMethod"][number],
  { did, collection, rkey }: { did: string; collection: string; rkey: string },
  { roots: [root], blocks }: Awaited<ReturnType<typeof readCar>>
) {
  assert(
    verificationMethod.controller === did,
    "Uncontrolled verification method"
  );
  debug("verificationMethod ok");

  const rootCbor = blocks.get(root);
  assert(rootCbor, "No root");

  const rootRecord = parseCommitData(cborToLexRecord(rootCbor));

  assert(
    await verifyCommitSig(
      rootRecord,
      `did:key:${verificationMethod.publicKeyMultibase}`
    ),
    "Invalid root commit signature"
  );
  debug("root sig ok");

  return await walkTree(`${collection}/${rkey}`, rootRecord.data, blocks);
}

async function walkTree(
  targetKey: string,
  hereId: CID,
  blocks: BlockMap,
  depth = 0
) {
  const hereRecord = blocks.get(hereId);

  assert(hereRecord, `No record for ${hereId}`);
  debug(depth, "walking", String(hereId));

  const hereSha = await crypto.subtle.digest("SHA-256", hereRecord);
  assert(
    td.decode(hereSha) === td.decode(hereId.multihash.digest),
    "Failed to verify hash of record"
  );
  debug(depth, "valid sha", hereId);

  const hereLex = parseNodeData(cborToLexRecord(hereRecord));

  const walk: Promise<RepoRecord>[] = new Array();

  if (hereLex.l && blocks.has(hereLex.l)) {
    debug(depth, "pushing left walk", hereLex.l);
    walk.push(walkTree(targetKey, hereLex.l, blocks, depth + 1));
  }

  let prevK = new Uint8Array();
  for (const { p, k: partialK, v, t } of hereLex.e) {
    const k = Uint8Array.from([...prevK.slice(0, p), ...partialK]);
    prevK = k;
    if (targetKey === td.decode(k)) {
      debug(depth, "detected target value", v, targetKey);
      return assertValidTarget(targetKey, v, blocks);
    }
    debug(depth, "passing non-target value", td.decode(k));
    if (t && blocks.has(t)) {
      debug(depth, "pushing right walk", t);
      walk.push(walkTree(targetKey, t, blocks, depth + 1));
    }
  }

  debug(depth, "passed node", hereId);
  // throws on purpose if `walk` is empty
  return Promise.any(walk);
}

async function assertValidTarget(targetKey: string, v: CID, blocks: BlockMap) {
  debug("validating target", targetKey, v);
  const targetRecord = blocks.get(v);
  const targetHash = await crypto.subtle.digest("SHA-256", targetRecord);
  assert(
    td.decode(targetHash) === td.decode(v.multihash.digest),
    "Failed to verify hash of target record"
  );
  debug("target hash ok");
  return cborToLexRecord(targetRecord);
}

async function main(agent: Agent, directory: DidResolver) {
  const fetchVm = async () => {
    const didDoc = await directory.resolve(did);
    assert(
      didDoc.verificationMethod.length,
      "No verification methods available"
    );
    return didDoc.verificationMethod[0];
  };

  const fetchCar = async () => {
    const { success, headers, data } = await agent.com.atproto.sync.getRecord({
      did,
      rkey,
      collection,
    });
    assert(success, `Failed to fetch record. ${headers}`);
    return data;
  };

  const vm = await fetchVm().catch(() => fetchVm());
  const car = await fetchCar().catch(() => fetchCar());

  const valid = await validateInclusion(
    vm,
    { did, collection, rkey },
    await readCar(car)
  );

  console.log("Valid record:", valid);
}

main(new Agent(agentArg), new DidResolver({ plcUrl }));
