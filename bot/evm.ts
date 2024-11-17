import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFileSync } from "fs";
import 'dotenv/config';

// function handleSkeet(
//  string memory _payload, 
//  uint256[2] memory _offsets, 
//  bytes32[] memory _proofHashes, 
//  uint8 _v, bytes32 _r, bytes32 _s)

type handleSkeetInput = {
    payload: string, // entire object to be hashed
    offsets: [number, number], // start of message, end msg
    proofHashes: string[],  // needs to have 1, which is sha256 hash of payload
    v: number, // ??
    r: string, // sc_r in goeo rust
    s: string, // sc_s in goeo rust
}

const provider = new JsonRpcProvider(process.env.RPC_URL, process.env.CHAIN_ID);
const privateKey = process.env.EVM_PRIVKEY;
const signer = new Wallet(privateKey, provider);

const GATEWAY_JSON = JSON.parse(readFileSync('SkeetGateway.json', 'utf-8'));

const GATEWAY_CONTRACT = new Contract(process.env.GATEWAY_ADDRESS, GATEWAY_JSON.abi, signer);
//console.log(GATEWAY_CONTRACT.interface.fragments);

async function sendSkeet(input: handleSkeetInput) {
    const tx = await GATEWAY_CONTRACT.handleSkeet(
        input.payload,
        input.offsets,
        input.proofHashes,
        input.v,
        input.r,
        input.s
    );

    const receipt = await tx.wait();
    console.log('Transaction:', receipt.transactionHash);
}

