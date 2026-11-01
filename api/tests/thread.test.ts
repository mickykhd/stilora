/**
 * Thread routes: reply nesting normalization (reply→reply joins the root
 * thread), chronological pagination, reply counts, deleted-root guard.
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
  const ws = await makeWorkspace(t, alice.cookie, "Thread WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");
  channel = await makeChannel(t, alice.cookie, wsId, "threads");
});
afterAll(async () => {
  await t?.close();
});

interface ThreadBody {
  parent: { id: string; content: string; replyCount: number } | null;
  replies: Array<{ id: string; content: string; threadParentId: string | null }>;
  nextCursor: string | null;
  hasMore: boolean;
}

describe("POST /api/messages/:messageId/replies", () => {
  test("reply attaches to the root and surfaces replyCount", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "a thoughtful question");

    const res = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: bob.cookie,
      body: { content: "a considered answer" },
    });
    expect(res.status).toBe(201);
    const d = await data<{ reply: { threadParentId: string | null; authorId: string } }>(res);
    expect(d.reply.threadParentId).toBe(root.id);
    expect(d.reply.authorId).toBe(bob.id);

    const thread = await data<ThreadBody>(
      await req(t, `/api/messages/${root.id}/replies`, { cookie: alice.cookie }),
    );
    expect(thread.parent?.id).toBe(root.id);
    expect(thread.replies).toHaveLength(1);
    expect(thread.parent?.replyCount).toBe(1);
  });

  test("reply-to-a-reply normalizes to the same root thread", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "nesting test root");
    const first = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "first reply" },
    });
    const firstReply = await data<{ reply: { id: string } }>(first);

    const nested = await req(t, `/api/messages/${firstReply.reply.id}/replies`, {
      method: "POST",
      cookie: bob.cookie,
      body: { content: "reply to the reply" },
    });
    expect(nested.status).toBe(201);
    const nestedBody = await data<{ reply: { threadParentId: string | null } }>(nested);
    expect(nestedBody.reply.threadParentId).toBe(root.id); // ← NOT the reply id

    // reading the thread from any of its messages yields the same root
    const viaReply = await data<ThreadBody>(
      await req(t, `/api/messages/${firstReply.reply.id}/replies`, { cookie: alice.cookie }),
    );
    expect(viaReply.parent?.id).toBe(root.id);
    expect(viaReply.replies).toHaveLength(2);
    expect(viaReply.parent?.replyCount).toBe(2);
  });

  test("replies are chronological (oldest first) with cursor paging", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "paging root");
    for (let i = 0; i < 3; i++) {
      const res = await req(t, `/api/messages/${root.id}/replies`, {
        method: "POST",
        cookie: alice.cookie,
        body: { content: `reply-${i}` },
      });
      expect(res.status).toBe(201);
    }

    const page1 = await data<ThreadBody>(
      await req(t, `/api/messages/${root.id}/replies?limit=2`, { cookie: alice.cookie }),
    );
    expect(page1.replies.map((r) => r.content)).toEqual(["reply-0", "reply-1"]);
    expect(page1.hasMore).toBe(true);

    const page2 = await data<ThreadBody>(
      await req(
        t,
        `/api/messages/${root.id}/replies?limit=2&cursor=${encodeURIComponent(page1.nextCursor as string)}`,
        { cookie: alice.cookie },
      ),
    );
    expect(page2.replies.map((r) => r.content)).toEqual(["reply-2"]);
    expect(page2.hasMore).toBe(false);
  });

  test("empty thread → parent present, zero replies", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "lonely root");
    const thread = await data<ThreadBody>(
      await req(t, `/api/messages/${root.id}/replies`, { cookie: alice.cookie }),
    );
    expect(thread.parent?.id).toBe(root.id);
    expect(thread.replies).toHaveLength(0);
    expect(thread.nextCursor).toBeNull();
  });

  test("replying to a deleted root → 400", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "doomed root");
    await req(t, `/api/messages/${root.id}`, { method: "DELETE", cookie: alice.cookie });
    const res = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "necro-reply" },
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("deleted");
  });

  test("invalid reply payload → 400", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "validation root");
    const res = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "" },
    });
    expect(res.status).toBe(400);
  });

  test("reply with someone else's storage key → 400", async () => {
    const root = await postMessage(t, alice.cookie, channel.id, "attachment root");
    const res = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: {
        content: "with file",
        attachments: [{ storageKey: `uploads/${bob.id}/stolen.png`, sizeBytes: 10 }],
      },
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("does not belong");
  });
});
