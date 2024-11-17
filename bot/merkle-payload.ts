import { ComAtprotoSyncGetRecord } from "@atproto/api";
import { cborEncode } from "@atproto/common";
import {
  cborToLexRecord,
  Commit,
  readCar,
  UnsignedCommit,
  verifyCommitSig,
} from "@atproto/repo";
import { CID } from "multiformats";
import assert from "node:assert";
import util from "node:util";
import { VerificationMethod } from "./watcher.js";

const isCommit3Lex = (c?: unknown): c is Commit | UnsignedCommit =>
  c != null &&
  typeof c == "object" &&
  typeof c["data"] === "object" &&
  c["data"] != null &&
  c["version"] === 3 &&
  typeof c["did"] == "string" &&
  typeof c["rev"] == "string";

const isSignedCommit3Lex = (c?: unknown): c is Commit =>
  isCommit3Lex(c) && c["sig"] instanceof Uint8Array && c["sig"].length === 64;

export type MerkleData = {
  rootSig: Commit["sig"];
  rootCbor: Uint8Array;
  treeCids: CID[];
  treeCbors: Uint8Array[];
};

export type MerkleSerialized = {
  /**  64-byte item */
  rootSig: Uint8Array;
  /** variable size */
  rootCbor: Uint8Array;
  /** variable array of 34-byte items */
  treeCids: Uint8Array[];
  /** variable array of variable items */
  treeCbors: Uint8Array[];
};

export const serializeMerkleData = ({
  rootSig,
  rootCbor,
  treeCids,
  treeCbors,
}: MerkleData): MerkleSerialized => ({
  rootSig,
  rootCbor,
  treeCids: treeCids.map((cid) => cid.bytes),
  treeCbors,
});

export const payloadFromPostRecord = async (
  verificationMethod: VerificationMethod,
  syncGetRecord: ComAtprotoSyncGetRecord.Response
): Promise<MerkleData> => {
  assert(
    syncGetRecord.success && syncGetRecord.data.length,
    util.inspect(syncGetRecord)
  );

  const { roots, blocks } = await readCar(syncGetRecord.data);

  assert(roots.length === 1, "Multi-root search unimplemented");

  const rootCid = roots[0];
  const rootBlock = blocks.get(rootCid);
  assert(rootBlock, "No root block");

  const { blockSig: rootSig, blockUnsigned: rootCbor } =
    await assertBlockSignature(verificationMethod, rootCid, rootBlock);

  const treeCids = blocks.cids();
  const treeCbors = treeCids.map((cid) => blocks.get(cid)!);

  return {
    rootSig,
    rootCbor,
    treeCids,
    treeCbors,
  };
};

const assertBlockSignature = async (
  verificationMethod: VerificationMethod,
  blockCid: CID,
  signedBlock: Uint8Array
) => {
  assert(verificationMethod.publicKeyMultibase);

  assert(
    blockCid.multihash.digest ===
      (await crypto.subtle.digest("SHA-256", signedBlock)),
    "Mismatched block checksum"
  );

  const lexBlock = cborToLexRecord(signedBlock);
  assert(isSignedCommit3Lex(lexBlock), "Block is not a signed commit");

  const didKey = `did:key:${verificationMethod.publicKeyMultibase}`;
  assert(await verifyCommitSig(lexBlock, didKey), "Invalid block signature");

  const { sig: blockSig, ...lexBlockUnsigned } = lexBlock;

  return {
    blockSig,
    blockUnsigned: cborEncode(lexBlockUnsigned),
  };
};
