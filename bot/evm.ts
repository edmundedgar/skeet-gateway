import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFileSync } from "fs";
import 'dotenv/config';
import { MerkleSerialized } from "./merkle-payload.js";


type handleSkeetInput = {
    data: MerkleSerialized,
    rkey: string
}

const provider = new JsonRpcProvider(process.env.RPC_URL, process.env.CHAIN_ID);
const privateKey = process.env.EVM_PRIVKEY;
const signer = new Wallet(privateKey, provider);

const GATEWAY_JSON = JSON.parse(readFileSync('SkeetGateway.json', 'utf-8'));

const GATEWAY_CONTRACT = new Contract(process.env.GATEWAY_ADDRESS, GATEWAY_JSON.abi, signer);
//console.log(GATEWAY_CONTRACT.interface.fragments);

async function sendSkeet(input: handleSkeetInput) {
    const tx = await GATEWAY_CONTRACT.handleSkeet(
        28, // v
        input.data.rootSig.slice(0,32),
        input.data.rootSig.slice(32),
        input.data.rootCbor,
        input.data.treeCids,
        input.data.treeCbors,
        input.rkey
    );

    const receipt = await tx.wait();
    console.log('Transaction:', receipt.transactionHash);
}

