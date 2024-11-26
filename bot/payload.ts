import { ComAtprotoSyncGetRecord } from "@atproto/api";
import { parseDataKey, readCarWithRoot, RecordPath } from "@atproto/repo";
import { VerificationMaterial } from "./did-document.js";
import { validateCommit, walkTree } from "./merkle.js";

export type ContractInput = RecordPath & {
  /** unsigned root commit cbor */
  commit: Uint8Array;
  /** signature for root commit cbor */
  sig: Uint8Array;
  /** target record (referred to by node.e[].v)*/
  target: Uint8Array;
  /** merkle tree nodes */
  treeNodes: Uint8Array[];
};

export const formatContractInput = async (
  verificationMaterial: VerificationMaterial,
  postRecord: ComAtprotoSyncGetRecord.Response["data"],
  targetKey: string
): Promise<ContractInput> => {
  const { root, blocks } = await readCarWithRoot(postRecord);
  const { collection, rkey } = parseDataKey(targetKey);

  const { sig, commit, nodeRef } = await validateCommit(
    verificationMaterial,
    root,
    blocks.get(root)!
  );
  blocks.delete(root);

  const targetCid = await walkTree({ collection, rkey }, nodeRef, blocks);
  const target = blocks.get(targetCid)!;
  blocks.delete(targetCid);

  const treeNodes = blocks.cids().map((cid) => blocks.get(cid)!);

  return { commit, sig, treeNodes, target, collection, rkey };
};
