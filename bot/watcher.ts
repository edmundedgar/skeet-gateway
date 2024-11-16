import { Bot } from "@skyware/bot";
import { Jetstream } from "@skyware/jetstream";
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

async function main() {
    console.log('starting bot');
    
    let bot = await initBot();
    let users = await getSubscribePostLikes(bot);
    bot.on('like', (event) => {
        console.log(`bot post liked: ${event.subject.uri}`);
        if(event.subject.uri == SUBSCRIBE_POST_URI) {
            users.push(event.user.did);
        }
    });
    // TODO - handle unliking to stop listening to a user
    console.log(`users: ${JSON.stringify(users, null, 2)}`);

    let jetstream = initJetstream(users);

    jetstream.onCreate("app.bsky.feed.post", (event) => {
	    console.log(`new post by ${event.did}`);
    });
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

function initJetstream(subscribers: did[]): Jetstream {
    return new Jetstream({
        wantedDids: subscribers,
        wantedCollections: ['app.bsky.feed.post'],
    });
}

main();
