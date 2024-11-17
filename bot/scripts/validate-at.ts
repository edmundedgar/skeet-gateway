import { Agent } from "@atproto/api";
import { DidResolver } from "@atproto/identity";
import { validateMerkleInclusion } from "../validate-merkle/record-inclusion.js";
import { readCar } from "@atproto/repo";
import assert from "node:assert";

import { TLSSocket } from 'node:tls';

console.log(TLSSocket)

const [
  atUriArg = "at://did:plc:mtq3e4mgt7wyjhhaniezej67/app.bsky.feed.post/3laydu3mgac2v",
  agentUrl = "https://bsky.network",
  plcUrl = "https://plc.directory",
] = process.argv.slice(2);

main(atUriArg, agentUrl, plcUrl);

async function main(atUriArg: string, agentUrl: string, plcUrl: string) {
  const agent = new Agent(agentUrl);
  const directory = new DidResolver({ plcUrl });
  const [_, did, collection, rkey] = atUriArg.match(
    /^at:\/\/(did:[\w\d]*:[\w\d]*)\/([\w\d\.]*)\/([\w\d]*)/
  );

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

  const vm = await retryOnce(fetchVm);
  const car = await retryOnce(fetchCar);

  const valid = await validateMerkleInclusion(
    vm,
    { did, collection, rkey },
    await readCar(car)
  );

  console.log("Valid record:", valid);
}

function retryOnce<T>(fn: () => T) {
  const retry = () => {
    console.warn(`Failed ${fn}, retrying...`);
    return fn();
  };

  try {
    const attempt = fn();
    if (attempt instanceof Promise) return attempt.catch(retry);
    return attempt;
  } catch (e) {
    return retry();
  }
}
