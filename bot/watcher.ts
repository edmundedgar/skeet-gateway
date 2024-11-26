import "dotenv/config";

import { getVerificationMaterial } from "@atproto/common";
import { formatDataKey } from "@atproto/repo";
import { Bot } from "@skyware/bot";
import { CommitCreateEvent, Jetstream } from "@skyware/jetstream";
import { getDidDocument } from "./did-document.js";
import {
  BOT_DID,
  BSKY_PASSWORD,
  BSKY_USERNAME,
  SUB_POST_KEY,
} from "./env/at.js";
import { formatContractInput } from "./payload.js";
import { syncGetRecord } from "./sync-repo.js";

async function initBot(): Promise<Bot> {
  const bot = new Bot();
  await bot.login({
    identifier: BSKY_USERNAME,
    password: BSKY_PASSWORD,
  });
  return bot;
}

const SUBSCRIBE_POST_URI = `at://${BOT_DID}/app.bsky.feed.post/${SUB_POST_KEY}`;

// check for the current list of DIDs that have liked
// the "like this post to subscribe" post
async function getSubscribePostLikes(bot: Bot) {
  const post = await bot.getPost(SUBSCRIBE_POST_URI);
  let getLikesResponse = await post.getLikes();
  let likerDids = getLikesResponse.likes;

  while (getLikesResponse.cursor) {
    getLikesResponse = await post.getLikes(getLikesResponse.cursor);
    likerDids.concat(getLikesResponse.likes);
  }

  return likerDids.map((profile) => profile.did);
}

function initJetstream(userDids: string[]): Jetstream {
  const stream = new Jetstream({
    wantedDids: userDids,
    wantedCollections: ["app.bsky.feed.post"],
  });
  // TODO - make callback customizable / do real thing
  stream.onCreate("app.bsky.feed.post", onUserPostCreation);

  stream.start();
  return stream;
}

function shouldPostMsgToChain(
  event: CommitCreateEvent<"app.bsky.feed.post">
): boolean {
  // TODO - real logic for determining whether user wants to upload
  return event.commit.record.text.startsWith("@skeetgate.bsky.social");
}

async function onUserPostCreation(
  event: CommitCreateEvent<"app.bsky.feed.post">
) {
  console.log("new post by", event.did, event.commit.record.text);
  if (shouldPostMsgToChain(event)) {
    const postRecord = syncGetRecord({
      did: event.did,
      collection: "app.bsky.feed.post",
      rkey: event.commit.rkey,
    });
    const verificationMaterial = getDidDocument(event.did).then(
      (doc) => getVerificationMaterial(doc, "#atproto")!
    );

    const payload = await formatContractInput(
      await verificationMaterial,
      await postRecord,
      formatDataKey(event.commit.collection, event.commit.rkey)
    );

    console.log("payload", payload);

    // TODO - upload to chain by calling sendSkeet()
  }
}

async function main() {
  console.log("starting bluesky bot...");

  let bot = await initBot();
  let users = await getSubscribePostLikes(bot);
  console.log(`users: ${JSON.stringify(users, null, 2)}`);

  let jetstream = initJetstream(users);

  bot.on("like", (event) => {
    if (event.subject.uri == SUBSCRIBE_POST_URI) {
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

  console.log("listening for users' posts");
}

main();
