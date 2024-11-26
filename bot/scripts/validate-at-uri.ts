import { Agent } from "@atproto/api";
import { getServiceEndpoint, getVerificationMaterial } from "@atproto/common";
import { parseDataKey, readCarWithRoot } from "@atproto/repo";
import { AtUri } from "@atproto/syntax";
import assert from "node:assert";
import { validateInclusion } from "../merkle.js";
import { DEFAULT_PDS_URL, DEFAULT_PLC_URL } from "../env/at.js";
import { getDidDocument } from "../did-document.js";
import { syncGetRecord } from "../sync-repo.js";

const [
  //atUriArg = "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3laydu3mgac2v",
  atUriArg = "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3lay2cpgw522v",
  plcUrl,
  pdsUrl,
] = process.argv.slice(2);

const debug = console.info;

main(new AtUri(atUriArg), plcUrl, pdsUrl);

async function main(atUri: AtUri, plcUrl = DEFAULT_PLC_URL, pdsUrl?: string) {
  const did = atUri.host;
  const { collection, rkey } = parseDataKey(atUri.pathname.slice(1));

  const didDoc = await retryOnce(() => getDidDocument(atUri.host, { plcUrl }));

  const vm = getVerificationMaterial(didDoc, "#atproto");
  assert(vm, "No verification material available");

  debug("Selected validation material", vm);

  const announcedService = getServiceEndpoint(didDoc, {
    id: "#atproto_pds",
    type: "AtprotoPersonalDataServer",
  });
  const serviceEndpoint = pdsUrl ?? announcedService ?? DEFAULT_PDS_URL;

  if (announcedService && pdsUrl !== announcedService)
    debug(
      `Document for ${did} announces PDS service`,
      serviceEndpoint,
      `but using ${pdsUrl}`
    );
  else if (serviceEndpoint) debug("Selected PDS service", serviceEndpoint);

  const agent = new Agent(serviceEndpoint);

  const car = await retryOnce(() => syncGetRecord(did, { collection, rkey }));

  const valid = await validateInclusion(
    vm,
    { collection, rkey },
    await readCarWithRoot(car)
  );

  console.log(valid);
}

function retryOnce<T>(fn: () => T): T;
function retryOnce<T>(fn: () => Promise<T>): Promise<T>;
function retryOnce(fn: () => unknown) {
  const retry = () => {
    console.warn(`Failed ${fn}, retrying...`);
    return fn();
  };

  try {
    const attempt = fn();
    if (attempt instanceof Promise) return attempt.catch(() => retry());
    else return attempt;
  } catch (e) {
    return retry();
  }
}
