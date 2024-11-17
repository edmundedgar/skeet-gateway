import { Bot } from "@skyware/bot";
import { CommitCreateEvent, Jetstream } from "@skyware/jetstream";
import WebSocket from "ws";
import 'dotenv/config';
import { AtpAgent, AtpAgentOptions, ComAtprotoSyncGetRecord } from "@atproto/api";
import { payloadFromPostRecord } from "./merkle-payload.js";
import { DidDocument } from "@atproto/common";
    
type did = string;
export type VerificationMethod = DidDocument["verificationMethod"][number];

async function initBot(): Promise<Bot> {
    const bot = new Bot();
    await bot.login({
        identifier: process.env.BSKY_USERNAME,
        password: process.env.BSKY_PASSWORD,
    });
    return bot;
}

const BOT_DID = process.env.BSKY_BOT_DID;
const SUB_POST_KEY = process.env.BSKY_SUBSCRIBE_POST_KEY;
const SUBSCRIBE_POST_URI = `at://${BOT_DID}/app.bsky.feed.post/${SUB_POST_KEY}`;
// check for the current list of DIDs that have liked
// the "like this post to subscribe" post
async function getSubscribePostLikes(bot: Bot): Promise<did[]> {
    const post = await bot.getPost(SUBSCRIBE_POST_URI);
    let getLikesResponse = await post.getLikes();
    let postLikers = getLikesResponse.likes;

    while (getLikesResponse.cursor) {
        getLikesResponse = await post.getLikes(getLikesResponse.cursor);
        postLikers.concat(getLikesResponse.likes);
    }

    return postLikers.map((profile) => profile.did);
}

function initJetstream(users: did[]): Jetstream {
    let stream = new Jetstream({
        ws: WebSocket,
        wantedDids: users,
        wantedCollections: ['app.bsky.feed.post'],
    });
    // TODO - make callback customizable / do real thing
    stream.onCreate('app.bsky.feed.post', onUserPostCreation);

    stream.start();
    return stream;
}

function shouldPostMsgToChain(event: CommitCreateEvent<"app.bsky.feed.post">): boolean {
    // TODO - real logic for determining whether user wants to upload
    return event.commit.record.text.startsWith('@skeetgate.bsky.social');
}

const AGENT_OPTIONS: AtpAgentOptions = {
    service: 'https://bsky.network',
};
const ATP_AGENT = new AtpAgent(AGENT_OPTIONS);

export const callSyncGetRecord = async (did: string, rkey: string): Promise<ComAtprotoSyncGetRecord.Response> => {
    return await ATP_AGENT.com.atproto.sync.getRecord({
        did,
        rkey,
        collection: 'app.bsky.feed.post',
    });
};


async function onUserPostCreation(event: CommitCreateEvent<"app.bsky.feed.post">) {
    console.log(`new post by ${event.did}\n  ${event.commit.record.text}`);
    if (shouldPostMsgToChain(event)) {
        const verificationMethod: VerificationMethod = {
            id: 'TODO',
            type: 'Ed25519VerificationKey2018',
            controller: event.did,
            publicKeyMultibase: 'TODO',
        };
        const getRecordResponse = await callSyncGetRecord(event.did, event.commit.rkey);
        const payload = await payloadFromPostRecord(verificationMethod, getRecordResponse);
        // TODO - upload to chain by calling sendSkeet()
    }
}

async function main() {
    console.log('starting bluesky bot...');

    let bot = await initBot();
    let users = await getSubscribePostLikes(bot);
    console.log(`users: ${JSON.stringify(users, null, 2)}`);
    
    let jetstream = initJetstream(users);

    bot.on('like', (event) => {
        if(event.subject.uri == SUBSCRIBE_POST_URI) {
            // TODO - linear scan for duplicate DIDs isn't efficient, optimize later
            if (!users.includes(event.user.did)) {
                console.log(`new subscriber: ${event.user.did}`);
                users.push(event.user.did);

                // watching a different set of DIDs requires re-init
                jetstream.close();
                jetstream = initJetstream(users);
            }
        }
    });
    // TODO - handle unliking to stop listening to a user

    console.log('listening for users\' posts');
}

main();
