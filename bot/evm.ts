import "dotenv/config";

import { Contract, JsonRpcProvider, Wallet } from "ethers";
import { GATEWAY_ABI, GATEWAY_ADDRESS } from "./env/contract.js";
import { EVM_PRIVKEY, EVM_RPC_URL } from "./env/evm.js";
import { ContractInput } from "./payload.js";

const provider = new JsonRpcProvider(EVM_RPC_URL);
const signer = new Wallet(EVM_PRIVKEY, provider);

const gatewayContract = new Contract(GATEWAY_ADDRESS, GATEWAY_ABI, signer);

export async function sendSkeet({
  sig,
  commit,
  treeNodes,
  target,
  collection,
  rkey,
}: ContractInput) {
  const handleSkeet = gatewayContract.getFunction("handleSkeet");
  const tx = await handleSkeet(
    28, // v
    sig.slice(0, 32), // r
    sig.slice(32), // s
    commit,
    treeNodes,
    target,
    collection,
    rkey
  );

  const receipt = await tx.wait();
  console.log("Transaction:", receipt.transactionHash);
}
