import { Agent } from "@atproto/api";
import { DidDocument } from "@atproto/common";
import { RecordPath } from "@atproto/repo";
import assert from "node:assert";
import { getPdsService } from "./did-document.js";

const debug = console.info;

export async function syncGetRecord(
  didDoc: DidDocument,
  { collection, rkey }: RecordPath,
  agentOpts?: ConstructorParameters<typeof Agent>[0]
) {
  const did = didDoc.id;
  const agent = new Agent(agentOpts ?? (await getPdsService(did)));
  debug("Fetching sync record for", did, collection, rkey);
  const r = await agent.com.atproto.sync.getRecord({ did, collection, rkey });
  assert(r.success, "Failed to fetch record");
  assert(r.data.length, "No data in record");
  return r.data;
}
