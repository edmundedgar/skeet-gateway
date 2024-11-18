import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFileSync } from "fs";
import 'dotenv/config';
import { MerkleData } from "./merkle-payload.js";

const provider = new JsonRpcProvider(process.env.RPC_URL);
const privateKey = process.env.EVM_PRIVKEY;
const signer = new Wallet(privateKey, provider);

const GATEWAY_JSON = JSON.parse(readFileSync('SkeetGateway.json', 'utf-8'));

const GATEWAY_CONTRACT = new Contract(process.env.GATEWAY_ADDRESS, GATEWAY_JSON.abi, signer);

export async function sendSkeet(data: MerkleData, rkey: string) {
    const tx = await GATEWAY_CONTRACT.handleSkeet(
        28,                           // v
        data.rootSig.slice(0,32),     // r
        data.rootSig.slice(32),       // s
        data.rootCbor,
        data.treeCids,
        data.treeCbors,
        rkey
    );

    const receipt = await tx.wait();
    console.log('Transaction:', receipt.transactionHash);
}

