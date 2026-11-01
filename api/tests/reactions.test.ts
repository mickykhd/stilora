/**
 * Reaction routes: idempotent add/remove, aggregation in message lists,
 * validation, activity feed side-effect for the message author.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  addMember,
  createTestApp,
  data,
  failure,
  makeChannel,
  makeWorkspace,
  postMessage,
  req,
  signIn,
  uniqueEmail,
  type SignedInUser,
  type TestApp,
} from "./helpers";

let t: TestApp;
let alice: SignedInUser;
let bob: SignedInUser;
let wsId: string;
let channel: { id: string };

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  const ws = await makeWorkspace(t, alice.cookie, "Reactions WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");
  channel = await makeChannel(t, alice.cookie, wsId, "react-y");
});
afterAll(async () => {
  await t?.close();
});

describe("PUT /api/messages/:messageId/reactions", () => {
  test("adding is idempotent; two users aggregate into one summary", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "react to me");

    const first = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "👍" },
    });
    expect(first.status).toBe(200);
    expect((await data<{ created: boolean }>(first)).created).toBe(true);

    const repeat = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "👍" },
    });
    expect(repeat.status).toBe(200);
    expect((await data<{ created: boolean }>(repeat)).created).toBe(false);

    const byBob = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "👍" },
    });
    expect((await data<{ created: boolean }>(byBob)).created).toBe(true);

    const list = await data<{
      messages: Array<{ id: string; reactions: Array<{ emoji: string; count: number; userIds: string[] }> }>;
    }>(await req(t, `/api/channels/${channel.id}/messages`, { cookie: alice.cookie }));

    const view = list.messages.find((m) => m.id === msg.id);
    expect(view?.reactions).toHaveLength(1);
    expect(view?.reactions[0]?.count).toBe(2);
    expect(new Set(view?.reactions[0]?.userIds)).toEqual(new Set([alice.id, bob.id]));
  });

  test("reaction notifies the message author (activity + unread push)", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "notify me via reaction");
    t.bus.clear();

    const res = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "🎉" },
    });
    expect(res.status).toBe(200);

    const feed = await data<{ notifications: Array<{ type: string; payload: unknown }>; unreadCount: number }>(
      await req(t, "/api/notifications", { cookie: alice.cookie }),
    );
    const note = feed.notifications.find((n) => n.type === "reaction.added");
    expect(note).toBeDefined();
    expect(feed.unreadCount).toBeGreaterThanOrEqual(1);

    const pushes = t.bus.find("unread.bumped");
    expect(pushes.some((p) => p.target === `user:${alice.id}`)).toBe(true);

    // no self-notification when the author reacts to their own message
    t.bus.clear();
    await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "🫠" },
    });
    expect(t.bus.find("unread.bumped").some((p) => p.target === `user:${alice.id}`)).toBe(false);
  });

  test("invalid emoji payloads → 400", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "validation target");
    const bad = ["", "two words", "x".repeat(33), "emo\u0007ji"];
    for (const emoji of bad) {
      const res = await req(t, `/api/messages/${msg.id}/reactions`, {
        method: "PUT",
        cookie: alice.cookie,
        body: { emoji },
      });
      expect(res.status).toBe(400);
    }
    const missing = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: {},
    });
    expect(missing.status).toBe(400);
    expect((await failure(missing)).error).toContain("validation failed");
  });

  test("reacting to a deleted message → 400", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "gone soon");
    await req(t, `/api/messages/${msg.id}`, { method: "DELETE", cookie: alice.cookie });
    const res = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "👍" },
    });
    expect(res.status).toBe(400);
  });
});

describe("DELETE /api/messages/:messageId/reactions", () => {
  test("removes once; second removal reports removed=false", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "removable");
    await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "🔥" },
    });

    const first = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "DELETE",
      cookie: alice.cookie,
      body: { emoji: "🔥" },
    });
    expect(first.status).toBe(200);
    expect((await data<{ removed: boolean }>(first)).removed).toBe(true);

    const second = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "DELETE",
      cookie: alice.cookie,
      body: { emoji: "🔥" },
    });
    expect(second.status).toBe(200);
    expect((await data<{ removed: boolean }>(second)).removed).toBe(false);
  });

  test("only removes MY reaction, not other users'", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "shared reaction");
    await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: alice.cookie,
      body: { emoji: "❤️" },
    });
    await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "❤️" },
    });

    const bobRemoves = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "DELETE",
      cookie: bob.cookie,
      body: { emoji: "❤️" },
    });
    expect((await data<{ removed: boolean }>(bobRemoves)).removed).toBe(true);

    const list = await data<{
      messages: Array<{ id: string; reactions: Array<{ count: number; userIds: string[] }> }>;
    }>(await req(t, `/api/channels/${channel.id}/messages`, { cookie: alice.cookie }));
    const view = list.messages.find((m) => m.id === msg.id);
    expect(view?.reactions[0]?.count).toBe(1);
    expect(view?.reactions[0]?.userIds).toEqual([alice.id]);
  });
});
