/**
 * DM routes: 1:1 creation + de-duplication, membership rules, message flow,
 * activity side-effects for the recipient, conversation listing.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  addMember,
  createTestApp,
  data,
  failure,
  makeChannel,
  makeWorkspace,
  req,
  signIn,
  uniqueEmail,
  type SignedInUser,
  type TestApp,
} from "./helpers";

let t: TestApp;
let alice: SignedInUser;
let bob: SignedInUser;
let carol: SignedInUser;
let wsId: string;

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  carol = await signIn(t, uniqueEmail("carol"));
  const ws = await makeWorkspace(t, alice.cookie, "DM WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");
  await addMember(t, wsId, carol.id, "member");
});
afterAll(async () => {
  await t?.close();
});

interface Conversation {
  id: string;
  workspaceId: string;
  kind: string;
  members: Array<{ id: string; name: string }>;
  lastMessageAt: string | null;
  lastMessagePreview: string | null;
}

async function startDm(cookie: string, userId: string): Promise<{ status: number; body: { conversation: Conversation; created: boolean } }> {
  const res = await req(t, `/api/workspaces/${wsId}/dm/conversations`, {
    method: "POST",
    cookie,
    body: { userId },
  });
  const status = res.status;
  return { status, body: await data(res) };
}

describe("POST /api/workspaces/:workspaceId/dm/conversations", () => {
  test("creates a 1:1 conversation; repeating returns the SAME one (created=false)", async () => {
    const first = await startDm(alice.cookie, bob.id);
    expect(first.status).toBe(201);
    expect(first.body.conversation.kind).toBe("dm");
    expect(first.body.created).toBe(true);
    // members exclude the viewer
    expect(first.body.conversation.members.map((m) => m.id)).toEqual([bob.id]);

    const second = await startDm(alice.cookie, bob.id);
    expect(second.status).toBe(200);
    expect(second.body.created).toBe(false);
    expect(second.body.conversation.id).toBe(first.body.conversation.id);

    // the other participant finds the same conversation too
    const fromBob = await startDm(bob.cookie, alice.id);
    expect(fromBob.body.created).toBe(false);
    expect(fromBob.body.conversation.id).toBe(first.body.conversation.id);
  });

  test("self-DM, non-member target and garbage ids → 400", async () => {
    const self = await req(t, `/api/workspaces/${wsId}/dm/conversations`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: alice.id },
    });
    expect(self.status).toBe(400);
    expect((await failure(self)).error).toContain("yourself");

    const outsider = await signIn(t, uniqueEmail("outsider"));
    const notMember = await req(t, `/api/workspaces/${wsId}/dm/conversations`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: outsider.id },
    });
    expect(notMember.status).toBe(400);
    expect((await failure(notMember)).error).toContain("not a member");

    const garbage = await req(t, `/api/workspaces/${wsId}/dm/conversations`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: "not-a-valid-id!" },
    });
    expect(garbage.status).toBe(400);
  });
});

describe("conversation messages", () => {
  test("send + read messages; recipient gets activity + unread push; sender doesn't", async () => {
    const dm = await startDm(alice.cookie, carol.id);
    const channelId = dm.body.conversation.id;
    t.bus.clear();

    const send = await req(t, `/api/dm/conversations/${channelId}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "hey carol" },
    });
    expect(send.status).toBe(201);
    const msg = await data<{ message: { authorId: string; content: string } }>(send);
    expect(msg.message.authorId).toBe(alice.id);

    // carol (recipient) was notified…
    const carolFeed = await data<{ notifications: Array<{ type: string }>; unreadCount: number }>(
      await req(t, "/api/notifications", { cookie: carol.cookie }),
    );
    expect(carolFeed.notifications.some((n) => n.type === "dm.message")).toBe(true);
    expect(carolFeed.unreadCount).toBeGreaterThanOrEqual(1);

    // …via a realtime push, while the SENDER gets nothing
    expect(t.bus.find("unread.bumped").some((p) => p.target === `user:${carol.id}`)).toBe(true);
    expect(t.bus.find("unread.bumped").some((p) => p.target === `user:${alice.id}`)).toBe(false);

    const read = await data<{ messages: Array<{ content: string }> }>(
      await req(t, `/api/dm/conversations/${channelId}/messages`, { cookie: carol.cookie }),
    );
    expect(read.messages.map((m) => m.content)).toContain("hey carol");
  });

  test("conversation list shows preview + lastMessageAt, ordered newest first", async () => {
    const dm = await startDm(alice.cookie, bob.id);
    await req(t, `/api/dm/conversations/${dm.body.conversation.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "latest word" },
    });

    const list = await data<{ conversations: Array<Conversation> }>(
      await req(t, "/api/dm/conversations", { cookie: alice.cookie }),
    );
    const convo = list.conversations.find((c) => c.id === dm.body.conversation.id);
    expect(convo).toBeDefined();
    expect(convo?.lastMessagePreview).toBe("latest word");
    expect(convo?.lastMessageAt).toBeTruthy();
    expect(convo?.members.map((m) => m.id)).toEqual([bob.id]);

    // newest activity first: the DM we just messaged sorts at index 0
    expect(list.conversations[0]?.id).toBe(dm.body.conversation.id);
  });

  test("a public channel id on the DM endpoint → 400 (not a DM)", async () => {
    const channel = await makeChannel(t, alice.cookie, wsId, "not-a-dm");
    const res = await req(t, `/api/dm/conversations/${channel.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "wrong door" },
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("direct message");
  });

  test("empty content → 400", async () => {
    const dm = await startDm(alice.cookie, bob.id);
    const res = await req(t, `/api/dm/conversations/${dm.body.conversation.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "   " },
    });
    expect(res.status).toBe(400);
  });

  test("invalid cursor / limit on DM messages → 400", async () => {
    const dm = await startDm(alice.cookie, bob.id);
    for (const query of ["cursor=not-a-cursor", "limit=999"]) {
      const res = await req(t, `/api/dm/conversations/${dm.body.conversation.id}/messages?${query}`, {
        cookie: alice.cookie,
      });
      expect(res.status).toBe(400);
    }
  });
});
