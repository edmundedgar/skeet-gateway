import { JsonRpcProvider, Wallet, Contract } from "ethers";
import { readFileSync } from "fs";
import 'dotenv/config';

const GATEWAY_ADDRESS = '0x2B95D0C4896b3b4b059DcEc005187eDcFf8ec0Ac';
const BBS_ADDRESS = '0x133b80cf22722561AbF837Ea841847AEEa6871Fb';

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


const RPC_URL = 'https://sepolia.drpc.org';
const CHAIN_ID = 11155111; // sepolia

const provider = new JsonRpcProvider(RPC_URL, CHAIN_ID);
const privateKey = process.env.EVM_PRIVKEY;
const signer = new Wallet(privateKey, provider);

const GATEWAY_JSON = JSON.parse(readFileSync('SkeetGateway.json', 'utf-8'));

const GATEWAY_CONTRACT = new Contract(GATEWAY_ADDRESS, GATEWAY_JSON.abi, signer);
//console.log(GATEWAY_CONTRACT);
console.log(GATEWAY_CONTRACT.interface.fragments);

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

