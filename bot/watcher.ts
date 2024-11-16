import { Bot } from "@skyware/bot";
import { CommitCreateEvent, Jetstream } from "@skyware/jetstream";
import WebSocket from "ws";
import 'dotenv/config';
    
const BOT_DID = 'did:plc:2xetvg6kr7scf2abxg3q5rvv';
type did = string;

async function initBot(): Promise<Bot> {
    const bot = new Bot();
    await bot.login({
        identifier: process.env.BSKY_USERNAME,
        password: process.env.BSKY_PASSWORD,
    });
    return bot;
}

const SUB_POST_ID = '3lb2f6j5lom22';
const SUBSCRIBE_POST_URI = `at://${BOT_DID}/app.bsky.feed.post/${SUB_POST_ID}`;
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
    stream.onCreate('app.bsky.feed.post', (event) => {
        console.log(`new post by ${event.did}\n  ${event.commit.record.text}`);
    });

    stream.start();
    return stream;
}

function shouldPostMsgToChain(event: CommitCreateEvent<"app.bsky.feed.post">): boolean {
    // TODO - real logic for determining whether user wants to upload
    return event.commit.record.text.startsWith('skeetgate');
}

function onUserPostCreation(event: CommitCreateEvent<"app.bsky.feed.post">) {
    console.log(`new post by ${event.did}\n  ${event.commit.record.text}`);
    if (shouldPostMsgToChain(event)) {
        // TODO - upload to chain
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
