## Skeet Gateway contracts

## Getting started

Make a .env with `PRIVATE_KEY`, `SEPOLIA_RPC_URL` and (for deployments) `ETHERSCAN_API_KEY` then run:

```
   source .env
```

Run `forge build`.

## Deployment

```
forge script --chain sepolia script/DeploySkeetGateway.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify --sig 'run(string,string)' <domain> <BBS bot>
```

eg.

```
forge script --chain sepolia script/DeploySkeetGateway.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify --sig 'run(string,string)' unconsensus.com bbs
```

This will make a deployment with a single initial bot (BBS bot) at `bbs.unconsensus.com`.

## Usage

### Adding a bot

The SkeetGateway has a modular design where you can add new functionality by registering a bot with its own name (eg "bbs") as a subdomain of a domain you are in charge of (the first test uses unconsensus.com), along with a parser contract that translates text into an action expressed in EVM bytecode. See `BBSMessageParser.sol` for a simple example of such a parser contract.

```
forge script --chain sepolia script/AddBot.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string,string)' <gateway> <parser address> <domain> <name of bot>
```

eg

```
forge script --chain sepolia script/AddBot.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string,string)' 0x4dfecc19ad271a5193777a9bccc11c9cf9869868 0xE7c13ff094869bcffC7D0cb4943D568d3AaB2aFC unconsensus.com bbs2
```


### Adding a domain

For the time being, adding a domain is permissioned, locked to the deployer of the contract. You can add one with

```
forge script --chain sepolia script/AddDomain.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string)' <gateway> <owner address> <domain>
```

eg

```
forge script --chain sepolia script/AddDomain.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string)' 0x4dfecc19ad271a5193777a9bccc11c9cf9869868 0x83dE7e64513e40b7C0f23Df654467178418AE19f "something.example.com"
```


### Sending a payload

We expect that payloads will be sent by our bot in bot/, implemented in Typescript, but you can also do it with forge.

Generate a payload .json file for the skeet using our python script or (needs fixing) typescript script. 

Then run:

```
forge script --chain sepolia script/SendPayload.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --sig 'run(address,string)' <address> <payload json file> --broadcast
```

eg

```
forge script --chain sepolia script/SendPayload.sol:SendPayload --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --sig 'run(address,string)' 0x4dfecc19ad271a5193777a9bccc11c9cf9869868 script/input/it_flies_like_a_beautiful_angel.json --broadcast
```

Note that the .json file can only be read from a directory marked as permitted in `foundry.toml`.
