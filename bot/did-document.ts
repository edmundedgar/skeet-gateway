import { getServiceEndpoint, getVerificationMaterial } from "@atproto/common";
import {
  type DidCache,
  type DidDocument,
  MemoryCache as DidMemoryCache,
  DidResolver,
  type DidResolverOpts,
} from "@atproto/identity";
import assert from "node:assert";
import { DEFAULT_PDS_URL, DEFAULT_PLC_URL } from "./env/at.js";

export type VerificationMaterial = Exclude<
  ReturnType<typeof getVerificationMaterial>,
  undefined
>;

//let exampleDid = "did:plc:7mnpet2pvof2llhpcwattscf";

const didCache: DidCache = new DidMemoryCache();

const getResolver = (opts?: DidResolver | DidResolverOpts) =>
  opts instanceof DidResolver
    ? opts
    : new DidResolver({
        plcUrl: DEFAULT_PLC_URL,
        didCache,
        ...opts,
      });

export async function getDidDocument(
  did: string,
  opts?: DidResolver | DidResolverOpts
): Promise<DidDocument> {
  const resolver = getResolver(opts);
  const didDoc = await resolver.resolve(did);
  assert(didDoc, "No did document found");
  return didDoc;
}

export async function getPdsService(
  did: string,
  opts?: DidResolver | DidResolverOpts
) {
  const resolver = getResolver(opts);
  const didDoc = await getDidDocument(did, resolver);

  return getServiceEndpoint(didDoc, { id: "#atproto_pds" }) ?? DEFAULT_PDS_URL;
}
