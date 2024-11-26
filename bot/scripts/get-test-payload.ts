import { getVerificationMaterial } from "@atproto/common";
import { formatDataKey, parseDataKey } from "@atproto/repo";
import { AtUri } from "@atproto/syntax";
import assert from "node:assert";
import util from "node:util";
import { getDidDocument } from "../did-document.js";
import { formatContractInput } from "../payload.js";
import { syncGetRecord } from "../sync-repo.js";

const debug = console.info;

Object.assign(Uint8Array.prototype, {
  [util.inspect.custom]: function (
    this: Uint8Array,
    _depth: number,
    _options: util.InspectOptions
  ) {
    return `\x1b[32m"${Buffer.from(this).toString("hex")}"\x1b[0m`;
  } satisfies util.CustomInspectFunction,
});

const [
  postUrl = "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3laydu3mgac2v",
] = process.argv.slice(2);

await main(new AtUri(postUrl));

async function main(atUri: AtUri) {
  debug("atUri", atUri);
  const did = atUri.host;
  assert(did, "No DID in URI");
  const { collection, rkey } = parseDataKey(atUri.pathname.slice(1));

  const didDoc = await getDidDocument(did);
  const vm = getVerificationMaterial(didDoc, "atproto");
  assert(vm);
  const postRecord = await syncGetRecord(didDoc, { collection, rkey });

  console.log({
    verificationMaterial: vm,
    query: { did, collection, rkey },
    contractInput: await formatContractInput(
      vm,
      postRecord,
      formatDataKey(collection, rkey)
    ),
  });
}
