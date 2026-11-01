/**
 * Message routes: creation (session-derived author, spoofing ignored),
 * attachments, edit/delete rules, and cursor pagination edge cases:
 * empty channel · exactly-50 boundary · deleted & threaded excluded ·
 * invalid cursors/limits.
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
import { messages } from "../src/db/schema";

let t: TestApp;
let alice: SignedInUser;
let bob: SignedInUser;
let carol: SignedInUser;
let wsId: string;
let channel: { id: string };

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  carol = await signIn(t, uniqueEmail("carol"));
  const ws = await makeWorkspace(t, alice.cookie, "Messages WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");
  await addMember(t, wsId, carol.id, "admin");
  channel = await makeChannel(t, alice.cookie, wsId, "general");
});
afterAll(async () => {
  await t?.close();
});

interface MessageView {
  id: string;
  authorId: string | null;
  content: string;
  editedAt: string | null;
  replyCount: number;
  pinned: boolean;
  reactions: Array<{ emoji: string; count: number }>;
  attachments: Array<{ storageKey: string }>;
}

interface ListBody {
  messages: MessageView[];
  nextCursor: string | null;
  hasMore: boolean;
}

describe("POST /api/channels/:channelId/messages", () => {
  test("creates a message; author comes from the SESSION, spoofed fields ignored", async () => {
    const res = await req(t, `/api/channels/${channel.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: {
        content: "legitimate message",
        // hostile fields — must be stripped by validation and never applied
        authorId: carol.id,
        author_id: carol.id,
        editedAt: "2020-01-01T00:00:00.000Z",
        deletedAt: "2020-01-01T00:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000000",
      },
    });
    expect(res.status).toBe(201);
    const d = await data<{ message: MessageView }>(res);
    expect(d.message.authorId).toBe(alice.id);
    expect(d.message.content).toBe("legitimate message");
    expect(d.message.editedAt).toBeNull();
    expect(d.message.replyCount).toBe(0);
    expect(d.message.pinned).toBe(false);
  });

  test("empty / whitespace / oversized content → 400", async () => {
    for (const content of ["", "   ", "x".repeat(12_001)]) {
      const res = await req(t, `/api/channels/${channel.id}/messages`, {
        method: "POST",
        cookie: alice.cookie,
        body: { content },
      });
      expect(res.status).toBe(400);
    }
  });

  test("non-string content → 400 (validation shape)", async () => {
    const res = await req(t, `/api/channels/${channel.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: 42 },
    });
    expect(res.status).toBe(400);
    const f = await failure(res);
    expect(f.error).toContain("validation failed");
    expect(f.status).toBe(400);
  });

  test("attachments: own key accepted, foreign key rejected", async () => {
    const ok = await req(t, `/api/channels/${channel.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: {
        content: "with a file",
        attachments: [
          {
            storageKey: `uploads/${alice.id}/2026/01/abc/pic.png`,
            mimeType: "image/png",
            sizeBytes: 1234,
            originalName: "pic.png",
          },
        ],
      },
    });
    expect(ok.status).toBe(201);
    const d = await data<{ message: MessageView }>(ok);
    expect(d.message.attachments).toHaveLength(1);
    expect(d.message.attachments[0]?.storageKey).toContain("uploads/");

    const foreign = await req(t, `/api/channels/${channel.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: {
        content: "stealing someone else's key",
        attachments: [{ storageKey: `uploads/${bob.id}/2026/01/abc/secret.png`, sizeBytes: 9 }],
      },
    });
    expect(foreign.status).toBe(400);
    expect((await failure(foreign)).error).toContain("does not belong");
  });
});

describe("edit & delete", () => {
  test("author edits → content + editedAt; others forbidden; spoofed author ignored", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "first draft");

    const edit = await req(t, `/api/messages/${msg.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { content: "second draft", authorId: bob.id },
    });
    expect(edit.status).toBe(200);
    const d = await data<{ message: MessageView }>(edit);
    expect(d.message.content).toBe("second draft");
    expect(d.message.editedAt).not.toBeNull();
    expect(d.message.authorId).toBe(alice.id); // unchanged — session rules

    const byOther = await req(t, `/api/messages/${msg.id}`, {
      method: "PATCH",
      cookie: bob.cookie,
      body: { content: "hijacked" },
    });
    expect(byOther.status).toBe(403);
  });

  test("plain member cannot delete another user's message; workspace admin can", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "admin will delete this");

    const byMember = await req(t, `/api/messages/${msg.id}`, {
      method: "DELETE",
      cookie: bob.cookie,
    });
    expect(byMember.status).toBe(403);

    const byAdmin = await req(t, `/api/messages/${msg.id}`, {
      method: "DELETE",
      cookie: carol.cookie,
    });
    expect(byAdmin.status).toBe(200);
  });

  test("delete is soft + idempotent; deleted messages leave the feed; editing them → 400", async () => {
    const msg = await postMessage(t, alice.cookie, channel.id, "about to vanish");

    const first = await req(t, `/api/messages/${msg.id}`, { method: "DELETE", cookie: alice.cookie });
    expect(first.status).toBe(200);
    const d = await data<{ message: { content: string; deletedAt: string } }>(first);
    expect(d.message.content).toBe(""); // content purged
    expect(d.message.deletedAt).toBeTruthy();

    const second = await req(t, `/api/messages/${msg.id}`, { method: "DELETE", cookie: alice.cookie });
    expect(second.status).toBe(200); // idempotent

    const list = await data<ListBody>(
      await req(t, `/api/channels/${channel.id}/messages?limit=100`, { cookie: alice.cookie }),
    );
    expect(list.messages.map((m) => m.id)).not.toContain(msg.id);

    const edit = await req(t, `/api/messages/${msg.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { content: "zombie" },
    });
    expect(edit.status).toBe(400);
    expect((await failure(edit)).error).toContain("deleted");
  });
});

describe("pagination", () => {
  test("empty channel → empty page, no cursor", async () => {
    const emptyChannel = await makeChannel(t, alice.cookie, wsId, "empty-room");
    const res = await req(t, `/api/channels/${emptyChannel.id}/messages`, { cookie: alice.cookie });
    expect(res.status).toBe(200);
    const d = await data<ListBody>(res);
    expect(d.messages).toHaveLength(0);
    expect(d.nextCursor).toBeNull();
    expect(d.hasMore).toBe(false);
  });

  test("exactly 50 messages → one full page, hasMore=false, no cursor", async () => {
    const fifty = await makeChannel(t, alice.cookie, wsId, "fifty-room");
    await seedMessages(fifty.id, 50);

    const res = await req(t, `/api/channels/${fifty.id}/messages?limit=50`, { cookie: alice.cookie });
    const d = await data<ListBody>(res);
    expect(d.messages).toHaveLength(50);
    expect(d.hasMore).toBe(false);
    expect(d.nextCursor).toBeNull();
  });

  test("51 messages → page of 50 + cursor; second page has the 51st; newest first", async () => {
    const fiftyOne = await makeChannel(t, alice.cookie, wsId, "fifty-one-room");
    await seedMessages(fiftyOne.id, 51);

    const page1 = await data<ListBody>(
      await req(t, `/api/channels/${fiftyOne.id}/messages?limit=50`, { cookie: alice.cookie }),
    );
    expect(page1.messages).toHaveLength(50);
    expect(page1.hasMore).toBe(true);
    expect(page1.nextCursor).toBeTruthy();

    // newest-first ordering
    const times = page1.messages.map((m) => m.content);
    expect(times[0]).toBe("seed-50");
    expect(times[49]).toBe("seed-1");

    const page2 = await data<ListBody>(
      await req(
        t,
        `/api/channels/${fiftyOne.id}/messages?limit=50&cursor=${encodeURIComponent(page1.nextCursor as string)}`,
        { cookie: alice.cookie },
      ),
    );
    expect(page2.messages).toHaveLength(1);
    expect(page2.messages[0]?.content).toBe("seed-0");
    expect(page2.hasMore).toBe(false);
    expect(page2.nextCursor).toBeNull();

    const seen = new Set([...page1.messages, ...page2.messages].map((m) => m.id));
    expect(seen.size).toBe(51);
  });

  test("threaded replies and deleted messages are excluded from the channel feed", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "mixed-room");
    const root = await postMessage(t, alice.cookie, ch.id, "root message");
    const reply = await req(t, `/api/messages/${root.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "a thread reply" },
    });
    expect(reply.status).toBe(201);
    const gone = await postMessage(t, alice.cookie, ch.id, "will be deleted");
    await req(t, `/api/messages/${gone.id}`, { method: "DELETE", cookie: alice.cookie });

    const list = await data<ListBody>(
      await req(t, `/api/channels/${ch.id}/messages`, { cookie: alice.cookie }),
    );
    const contents = list.messages.map((m) => m.content);
    expect(contents).toContain("root message");
    expect(contents).not.toContain("a thread reply");
    expect(contents).not.toContain("");

    // replyCount surfaced on the root
    const rootView = list.messages.find((m) => m.id === root.id);
    expect(rootView?.replyCount).toBe(1);
  });

  test("invalid limit / cursor → 400", async () => {
    for (const query of ["limit=0", "limit=101", "limit=abc", "cursor=not-base64-json"]) {
      const res = await req(t, `/api/channels/${channel.id}/messages?${query}`, {
        cookie: alice.cookie,
      });
      expect(res.status).toBe(400);
    }
  });
});

/** Bulk-seed root messages directly (fast pagination fixtures). */
async function seedMessages(channelId: string, count: number): Promise<void> {
  const base = Date.parse("2026-01-01T00:00:00.000Z");
  const values = Array.from({ length: count }, (_, i) => ({
    channelId,
    authorId: alice.id,
    content: `seed-${i}`,
    createdAt: new Date(base + i * 1_000),
    updatedAt: new Date(base + i * 1_000),
  }));
  await t.db.insert(messages).values(values);
}
