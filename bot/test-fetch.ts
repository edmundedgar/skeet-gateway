import assert from "node:assert";
import {
  payloadFromPostRecord,
  serializeMerkleData,
} from "./merkle-payload.js";
import { DidResolver } from "@atproto/identity";
import { Agent } from "@atproto/api";

import util from "node:util";

const FgGreen = "\x1b[32m";

Object.assign(Uint8Array.prototype, {
  [util.inspect.custom]: function (
    this: Uint8Array,
    depth: number,
    options: util.InspectOptions
  ) {
    return `\x1b[32m"${Buffer.from(this).toString("hex")}"\x1b[0m`;
  } satisfies util.CustomInspectFunction,
});

const postUrl =
  "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3laydu3mgac2v";

const [_, did, collection, rkey] = postUrl.match(
  /^at:\/\/(did:[\w\d]*:[\w\d]*)\/([\w\d\.]*)\/([\w\d]*)/
);

const didRes = new DidResolver({});
const didDoc = await didRes.resolve(did);

const [vm] = didDoc.verificationMethod!;
assert(vm);

const postRecord = await new Agent(
  "https://bsky.network"
).com.atproto.sync.getRecord({
  did,
  rkey,
  collection,
});

const merkleData = await payloadFromPostRecord(vm, postRecord);

console.log({
  verificationMethod: vm,
  query: { did, collection, rkey },
  merkleData: serializeMerkleData(merkleData),
});
