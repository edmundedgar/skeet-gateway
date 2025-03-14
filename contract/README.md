## Skeet Gateway contracts

## Getting started

Make a .env with `PRIVATE_KEY`, `SEPOLIA_RPC_URL` and (for deployments) `ETHERSCAN_API_KEY` then run:

```
   source .env
```

Run `forge build`.

## Deployment

### Deploy everything

Deploy the SkeetGateway and various bots as definied in `/script/input/deploy_parameters.json`

```
forge script --chain sepolia script/DeployEverything.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify

```

### Limited deployment

```
forge script --chain sepolia script/DeploySkeetGateway.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify --sig 'run(string,string)' <domain> <BBS bot>
```

eg.

```
forge script --chain sepolia script/DeploySkeetGateway.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --broadcast --verify --sig 'run(string,string)' unconsensus.com bbs
```

This will make a deployment with a single initial bot (BBS bot) at `bbs.unconsensus.com`.

Other commands reference the gateway so you may want to set the environmental variable $SKEET_GATEWAY to its address.

## Usage

### Adding a bot

The SkeetGateway has a modular design where you can add new functionality by registering a bot with its own name (eg "bbs") as a subdomain of a domain you are in charge of (the first test uses unconsensus.com), along with a parser contract that translates text into an action expressed in EVM bytecode. See `BBSMessageParser.sol` for a simple example of such a parser contract.

```
forge script --chain sepolia script/AddBot.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string,string,string)' <gateway> <parser address> <domain> <name of bot> <metadata>
```

eg

```
forge script --chain sepolia script/AddBot.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string,string)' $SKEET_GATEWAY 0xE7c13ff094869bcffC7D0cb4943D568d3AaB2aFC unconsensus.com bbs2 ""
```


### Adding a domain

For the time being, adding a domain is permissioned, locked to the deployer of the contract. You can add one with

```
forge script --chain sepolia script/AddDomain.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string)' <gateway> <owner address> <domain>
```

eg

```
forge script --chain sepolia script/AddDomain.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --broadcast --sig 'run(address,address,string)' $SKEET_GATEWAY 0x83dE7e64513e40b7C0f23Df654467178418AE19f "something.example.com"
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
forge script --chain sepolia script/SendPayload.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --sig 'run(address,string)' $SKEET_GATEWAY script/input/it_flies_like_a_beautiful_angel.json --broadcast
```

Note that the .json file can only be read from a directory marked as permitted in `foundry.toml`.


## Other useful commands

### Deploying and adding the reality.eth bots (example)

```
forge script --chain sepolia script/AddRealityETHBots.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --sig "run(address,address,address,string,string,string,string)" <gateway> <reality.eth> <arbitrator> <reality.eth url prefix> "bot.reality.eth.link" "askqv1" "answerv1" --broadcast
```

eg

```
forge script --chain sepolia script/AddRealityETHBots.sol --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL --sig "run(address,address,address,string,string,string,string)" $SKEET_GATEWAY 0xaf33DcB6E8c5c4D9dDF579f53031b514d19449CA 0x05b942faecfb3924970e3a28e0f230910cedff45 'https://reality.eth.link/app/#!/network/11155111/contract/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca/token/ETH/question/0xaf33dcb6e8c5c4d9ddf579f53031b514d19449ca-0x' "bot.reality.eth.link" "askqv1" "answerv1" --broadcast

You should fund your Safe before trying to use the "answer question" feature of the reality.eth bot.
```
