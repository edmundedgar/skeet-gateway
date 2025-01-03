# Bots and parsing modules

## Examples

 `tip.bot.something <address> <amount>` will send a tip of the specified amount to the specified address

 `add.dao.bot.something <mydao> <address>` will add an address to control a DAO by the name <mydao>

## Principles

A single gateway, the SkeetGateway, is responsible for handling all kinds of different bots. These may be build and operated by different people.

In principle, sending a message addressed to a bot is considered a sign that you know what that bot does and you assent to let it control your assets.

However, as far as possible the naming should make it obvious that you are messaging an asset-controlling bot. It should also prevent people from retroactively attaching meaning to existing skeets.

## The domain allow-list

The SkeetGateway manages a list of domains, and an owner address for each domain that has the permission to add bots under it. Currently the ability to add domains is permissioned.

TODO: We might want to let signers add their own domains, eg by calling `@enable.bot.something somedomain.com`. Alternatively we could put this in the control of a curated directory (kleros curate or similar).

## Parser modules

Each bot name, eg `pay.skeetgateway.eth.link`, is paired with a parser contract implementing the interface `IMessageParser`.

When handling a message, the SkeetGateway will first read the initial characters representing the bot name and to find out which parser it should use to interpret the message.

It will then send the content to the parser contract. The parser contract returns an address, a value and some calldata, and the SkeetGateway executes this from the signer's currently selected Safe.

## Registering parsers

You can register a parser under a domain you control by calling the SkeetGateway with the method `addBot`.

## Caller metadata

Some parsers may need additional context that is not needed by others. For example, the reality.eth "answer question" bot needs the reply parent content so it knows what question you are replying to. This can be signalled when registering the parser by passing in a string representing a JSON-encoded list of settings. Currently the only value recognized is `{reply: 1}`.
