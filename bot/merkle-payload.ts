import { ComAtprotoSyncGetRecord } from "@atproto/api";
import { cborEncode } from "@atproto/common";
import { RepoRecord } from "@atproto/lexicon";
import {
  cborToLexRecord,
  readCar,
  schema,
  verifyCommitSig,
} from "@atproto/repo";
import { CID } from "multiformats";
import assert from "node:assert";
import util from "node:util";
import { VerificationMethod } from "./watcher.js";

const parseCommitData = (r: RepoRecord) => schema.commit.parse(r);

export type MerkleData = {
  /**  64-byte item */
  rootSig: Uint8Array;
  /** variable size */
  rootCbor: Uint8Array;
  /** variable array of 34-byte items */
  treeCids: Uint8Array[];
  /** variable array of variable items */
  treeCbors: Uint8Array[];
};

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
    treeCids: treeCids.map((cid) => cid.bytes),
    treeCbors,
  };
};

const assertBlockSignature = async (
  verificationMethod: VerificationMethod,
  blockCid: CID,
  signedBlock: Uint8Array
) => {
  assert(verificationMethod.publicKeyMultibase);

  const blockSha = Buffer.from(blockCid.multihash.digest).toString("hex");
  const checkBlockSha = Buffer.from(
    await crypto.subtle.digest("SHA-256", signedBlock)
  ).toString("hex");
  assert(
    blockSha === checkBlockSha,
    `Mismatched block checksum: ${blockSha} !== ${checkBlockSha}`
  );

  const lexBlock = parseCommitData(cborToLexRecord(signedBlock));

  assert(
    await verifyCommitSig(
      lexBlock,
      `did:key:${verificationMethod.publicKeyMultibase}`
    ),
    "Invalid block signature"
  );

  const { sig: blockSig, ...lexBlockUnsigned } = lexBlock;

  return {
    blockSig,
    blockUnsigned: cborEncode(lexBlockUnsigned),
  };
};
