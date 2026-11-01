/**
 * Pin routes: pin/unpin idempotency, listing, message-scope validation,
 * pinned flag in message enrichment, author notification.
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
  const ws = await makeWorkspace(t, alice.cookie, "Pins WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");
  channel = await makeChannel(t, alice.cookie, wsId, "pinned");
});
afterAll(async () => {
  await t?.close();
});

describe("POST /api/channels/:channelId/pins", () => {
  test("pin is idempotent, listed, flagged in the feed, and notifies the author", async () => {
    t.bus.clear();
    const msg = await postMessage(t, alice.cookie, channel.id, "pin worthy");

    const first = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    expect(first.status).toBe(201);
    const d = await data<{ created: boolean; pin: { messageId: string; pinnedBy: string } }>(first);
    expect(d.created).toBe(true);
    expect(d.pin.pinnedBy).toBe(alice.id);

    const repeat = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    expect(repeat.status).toBe(200);
    expect((await data<{ created: boolean }>(repeat)).created).toBe(false);

    const pinsList = await data<{
      pins: Array<{ messageId: string; pinnedBy: string; message: { content: string } }>;
    }>(await req(t, `/api/channels/${channel.id}/pins`, { cookie: alice.cookie }));
    expect(pinsList.pins.map((p) => p.messageId)).toContain(msg.id);
    expect(pinsList.pins[0]?.message.content).toBe("pin worthy");

    const feed = await data<{ messages: Array<{ id: string; pinned: boolean }> }>(
      await req(t, `/api/channels/${channel.id}/messages`, { cookie: alice.cookie }),
    );
    expect(feed.messages.find((m) => m.id === msg.id)?.pinned).toBe(true);

    // activity for the pinned message's author (bob pinned alice's message?)
    // here alice pinned her own → no self-notification, but pin event fired:
    expect(t.bus.find("pin.changed").length).toBeGreaterThanOrEqual(1);
  });

  test("pin by another member notifies the author through the activity feed", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "pinned by bob");
    const res = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: bob.cookie,
      body: { messageId: msg.id },
    });
    expect(res.status).toBe(201);

    const feed = await data<{ notifications: Array<{ type: string; payload: { messageId?: string } }> }>(
      await req(t, "/api/notifications", { cookie: alice.cookie }),
    );
    const note = feed.notifications.find(
      (n) => n.type === "message.pinned" && n.payload.messageId === msg.id,
    );
    expect(note).toBeDefined();
  });

  test("message not in this channel → 404; garbage id → 400; deleted → 404", async () => {
    const otherChannel = await makeChannel(t, alice.cookie, wsId, "other-pin-room");
    const foreignMsg = await postMessage(t, alice.cookie, otherChannel.id, "elsewhere");

    const foreign = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: foreignMsg.id },
    });
    expect(foreign.status).toBe(404);

    const garbage = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: "not-a-uuid" },
    });
    expect(garbage.status).toBe(400);

    const deleted = await postMessage(t, alice.cookie, channel.id, "deleted before pinning");
    await req(t, `/api/messages/${deleted.id}`, { method: "DELETE", cookie: alice.cookie });
    const pinDeleted = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: deleted.id },
    });
    expect(pinDeleted.status).toBe(404);
  });

  test("invalid payload → 400", async () => {
    const res = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: {},
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("validation failed");
  });
});

describe("DELETE /api/channels/:channelId/pins", () => {
  test("unpin removes once; second attempt removed=false; foreign → 404", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "unpin me");
    await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });

    const first = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "DELETE",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    expect(first.status).toBe(200);
    expect((await data<{ removed: boolean }>(first)).removed).toBe(true);

    const second = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "DELETE",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    expect(second.status).toBe(200);
    expect((await data<{ removed: boolean }>(second)).removed).toBe(false);

    const otherChannel = await makeChannel(t, alice.cookie, wsId, "unpin-other");
    const foreignMsg = await postMessage(t, alice.cookie, otherChannel.id, "not here");
    const foreign = await req(t, `/api/channels/${channel.id}/pins`, {
      method: "DELETE",
      cookie: alice.cookie,
      body: { messageId: foreignMsg.id },
    });
    expect(foreign.status).toBe(404);
  });

  test("pins of deleted messages disappear from the list", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "pin then delete");
    await req(t, `/api/channels/${channel.id}/pins`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    await req(t, `/api/messages/${msg.id}`, { method: "DELETE", cookie: alice.cookie });

    const list = await data<{ pins: Array<{ messageId: string }> }>(
      await req(t, `/api/channels/${channel.id}/pins`, { cookie: alice.cookie }),
    );
    expect(list.pins.map((p) => p.messageId)).not.toContain(msg.id);
  });
});
