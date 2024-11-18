import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFileSync } from "fs";
import 'dotenv/config';
import { MerkleData } from "./merkle-payload.js";


type handleSkeetInput = {
    data: MerkleData,
    rkey: string
}

const provider = new JsonRpcProvider(process.env.RPC_URL);
const privateKey = process.env.EVM_PRIVKEY;
const signer = new Wallet(privateKey, provider);

const GATEWAY_JSON = JSON.parse(readFileSync('SkeetGateway.json', 'utf-8'));

const GATEWAY_CONTRACT = new Contract(process.env.GATEWAY_ADDRESS, GATEWAY_JSON.abi, signer);
//console.log(GATEWAY_CONTRACT.interface.fragments);

async function sendSkeet(input: handleSkeetInput) {
    const tx = await GATEWAY_CONTRACT.handleSkeet(
        28,                                 // v
        input.data.rootSig.slice(0,32),     // r
        input.data.rootSig.slice(32),       // s
        input.data.rootCbor,
        input.data.treeCids,
        input.data.treeCbors,
        input.rkey
    );

    const receipt = await tx.wait();
    console.log('Transaction:', receipt.transactionHash);
}

