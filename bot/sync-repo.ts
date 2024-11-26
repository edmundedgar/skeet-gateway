import assert from "node:assert";

import { DEFAULT_PDS_URL } from "./env/at.js";
import { Agent, ComAtprotoSyncGetRecord } from "@atproto/api";

const debug = console.info;

export async function syncGetRecord(
  { did, collection, rkey }: ComAtprotoSyncGetRecord.QueryParams,
  agentOpts?: ConstructorParameters<typeof Agent>[0]
) {
  const agent = new Agent(agentOpts ?? DEFAULT_PDS_URL);
  debug("Fetching sync record for", did, collection, rkey);
  const r = await agent.com.atproto.sync.getRecord({ did, collection, rkey });
  assert(r.success, "Failed to fetch record");
  assert(r.data.length, "No data in record");
  return r.data;
}
