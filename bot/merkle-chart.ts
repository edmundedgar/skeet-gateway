import { AtpAgent } from "@atproto/api";
import { DidResolver } from "@atproto/identity";
import { RepoRecord } from "@atproto/lexicon";
import { cborToLexRecord, Commit, readCar } from "@atproto/repo";
import base32 from "base32";
import { CID } from "multiformats";
import assert from "node:assert";
import fs from "node:fs/promises";
import util, { CustomInspectFunction } from "node:util";

const td = new TextDecoder();

Object.assign(Uint8Array.prototype, {
  [util.inspect.custom]: function (
    this: InstanceType<typeof Uint8Array>,
    depth,
    options
  ) {
    const b32 = base32.encode(this) as string;
    const encoded = b32.length < 128 ? b32 : b32.slice(0, 128 - 3) + "...";
    return `\x1b[35mUint8Array(\x1b[0m${this.length}\x1b[35m)${encoded}\x1b[0m`;
  } satisfies CustomInspectFunction,
});

Object.assign(CID.prototype, {
  [util.inspect.custom]: function (
    this: InstanceType<typeof CID>,
    depth,
    options
  ) {
    return `\x1b[35mCID(${this.toString()})/${Object.keys(this)}\x1b[0m`;
  } satisfies CustomInspectFunction,
});

const [did, rkey, collection = "app.bsky.feed.post"] = process.argv.slice(2);

const chartHead = [
  "```mermaid",
  "flowchart LR",
  "classDef _noblock fill:#aaa",
  "classDef _root fill:#f0f",
  "classDef _tree fill:#77f",
  "classDef _value fill:#f70",
  "classDef _other fill:#0f0",
  "classDef _e fill:#0f0",
  "classDef _hash fill:#ddd",
];
const chartEnd = ["```"];

const agent = new AtpAgent({ service: "https://bsky.network" });
const didRes = new DidResolver({});

const didDoc = await didRes.resolve(did);
assert(didDoc);
console.log(did, didDoc);

const [vm] = didDoc.verificationMethod!;
assert(vm);

let rootCid: CID | undefined;
let rootBlock: Uint8Array | undefined;
let rootRecord: Commit | undefined;

const post = await agent.com.atproto.sync.getRecord({ collection, did, rkey });

let chart: string[] = [];

const cidHash = (it: CID): string => base32.encode(it.multihash.digest);
const cidStr = (it: CID): string => `${it}(${cidHash(it)})`;

await graphPost(post.data);

async function graphPost(bin: Uint8Array) {
  const { roots, blocks } = await readCar(bin);
  assert(roots.length === 1);
  rootCid = roots[0];
  rootBlock = blocks.get(rootCid)!;
  rootRecord = cborToLexRecord(rootBlock) as Commit;

  console.log({ rootCid, rootBlock, rootRecord });

  blocks.delete(rootCid);
  const rootRef = rootRecord.data;
  chart.push(`${cidStr(rootRef)}:::_root`);

  console.log(blocks);

  const visited = new Set<string>();

  const queue = [rootRef];
  let i = 0;
  while (i < queue.length) {
    const cid = queue[i++];
    if (!cid) {
      console.log("no cid", i, queue.length, cid, queue);
      continue;
    }

    if (visited.has(String(cid))) {
      console.warn("previously visited " + cid);
      continue;
    }
    visited.add(String(cid));

    const bytes = blocks.get(cid);

    if (!bytes) {
      console.log("no block for cid", cidStr(cid));
      chart.push(`${cidStr(cid)}:::_noblock`);
      continue;
    }

    const { l, e, ...record } = cborToLexRecord(bytes) as
      | RepoRecord & {
          l?: CID | null;
          e?: { k: Uint8Array; p: number; t?: CID | null; v: CID }[];
        };

    console.log(String(cid), Object.fromEntries(Object.entries(cid)), {
      ...(l || e?.length ? { l, e } : {}),
      ...(Object.keys(record).length ? { record } : {}),
    });

    if (l) {
      chart.push(`${cidStr(cid)} --left--> ${cidStr(l)}`);
      queue.push(l);
    }
    if (e) {
      let prevK: Uint8Array = new Uint8Array();
      const es = e.map(({ p, k, t, v }) => {
        if (v) {
          if (blocks.has(v)) {
            console.log("v", cidStr(v));
            queue.push(v);
            chart.push(`${cidStr(cid)} ==value==o ${cidStr(v)}:::_value`);
          } else console.log("no v", cidStr(v));
        }
        if (t) {
          if (blocks.has(t)) {
            console.log("t", cidStr(t));
            queue.push(t);
            chart.push(`${cidStr(cid)} -.-o ${cidStr(t)}:::_tree`);
          } else console.log("no t", cidStr(t));
        }
        const rebuilt = new Uint8Array([...prevK.slice(0, p), ...k]);
        prevK = rebuilt;
        return td.decode(rebuilt);
      });

      for (const esKey of es) {
        console.log("e", cidStr(cid), esKey);
        chart.push(`${cidStr(cid)} --.--> ${esKey}:::_e`);
      }
    }
    if (!l && !e?.length && Object.keys(record).length) {
      console.log("unknown?", cidStr(cid), record);
      chart.push(`${cidStr(cid)}`);
    }
  }

  await fs.writeFile(
    "chart.md",
    [
      ...chartHead,
      ...chart, //.sort((a, b) => a.localeCompare(b)),
      ...chartEnd,
    ].join("\n")
  );
}
