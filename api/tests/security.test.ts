/**
 * Security tests:
 *  - IDOR: user A can neither read nor write workspace B — every scoped route
 *    (opposite direction from auth.matrix, which proves B ↛ A)
 *  - oversized payloads → 413 (both declared Content-Length and real body)
 *  - spoofed author / identity fields are ALWAYS ignored (session wins),
 *    verified against the database, not just the response
 *  - malformed JSON → 400, tampered session → 401, unknown route → 404
 *  - CORS: allow-list enforced, unknown origins denied with no CORS headers
 *  - x-request-id echoed on success and failure
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { eq } from "drizzle-orm";
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
import { messages, workspaceMembers } from "../src/db/schema";

let t: TestApp;
let alice: SignedInUser; // attacker with a VALID session
let bob: SignedInUser; // victim (workspace B owner)
let carol: SignedInUser; // second member of alice's test workspaces
let bobWs: string;
let bobChannel: { id: string };
let bobMessage: string;
let bobDmId: string;

beforeAll(async () => {
  // small body cap so the 413 tests stay light
  t = await createTestApp({ MAX_BODY_BYTES: "4096" });
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  carol = await signIn(t, uniqueEmail("carol"));

  const ws = await makeWorkspace(t, bob.cookie, "Victim Corp");
  bobWs = ws.id;
  bobChannel = await makeChannel(t, bob.cookie, bobWs, "private-ops", "private");
  bobMessage = (await postMessage(t, bob.cookie, bobChannel.id, "victim says hi")).id;

  // bob's DM (with a second workspace member — alice is deliberately outside)
  const second = await signIn(t, uniqueEmail("victim2"));
  await t.db
    .insert(workspaceMembers)
    .values({ workspaceId: bobWs, userId: second.id, role: "member" })
    .onConflictDoNothing();
  const dm2 = await req(t, `/api/workspaces/${bobWs}/dm/conversations`, {
    method: "POST",
    cookie: bob.cookie,
    body: { userId: second.id },
  });
  expect(dm2.status).toBe(201);
  bobDmId = (await data<{ conversation: { id: string } }>(dm2)).conversation.id;
});
afterAll(async () => {
  await t?.close();
});

describe("IDOR: alice (valid session) vs bob's workspace", () => {
  const attacks: Array<{ name: string; method: string; path: string; body?: unknown; prefix?: string }> = [
    { name: "read workspace", method: "GET", path: "" },
    { name: "read members", method: "GET", path: "/members" },
    { name: "create invite", method: "POST", path: "/invites", body: {} },
    { name: "list channels", method: "GET", path: "/channels" },
    { name: "create channel", method: "POST", path: "/channels", body: { name: "evil-chan" } },
    {
      name: "start dm in foreign ws",
      method: "POST",
      path: "/dm/conversations",
      body: { userId: "anyone" },
    },
    { name: "read foreign channel", method: "GET", path: "", prefix: "channel" },
    { name: "patch foreign channel", method: "PATCH", path: "", prefix: "channel", body: { topic: "mine now" } },
    { name: "post into foreign channel", method: "POST", path: "/messages", prefix: "channel", body: { content: "hi" } },
    { name: "read foreign messages", method: "GET", path: "/messages", prefix: "channel" },
    { name: "read foreign pins", method: "GET", path: "/pins", prefix: "channel" },
    { name: "pin in foreign channel", method: "POST", path: "/pins", prefix: "channel", body: { messageId: "" } },
    { name: "mark foreign channel read", method: "POST", path: "/read", prefix: "channel", body: { messageId: "" } },
    { name: "foreign dm messages (get)", method: "GET", path: "/messages", prefix: "dm" },
    { name: "foreign dm messages (post)", method: "POST", path: "/messages", prefix: "dm", body: { content: "sneak" } },
    { name: "edit foreign message", method: "PATCH", path: "", prefix: "message", body: { content: "edited" } },
    { name: "delete foreign message", method: "DELETE", path: "", prefix: "message" },
    { name: "read foreign thread", method: "GET", path: "/replies", prefix: "message" },
    { name: "reply to foreign message", method: "POST", path: "/replies", prefix: "message", body: { content: "hi" } },
    { name: "react to foreign message", method: "PUT", path: "/reactions", prefix: "message", body: { emoji: "👍" } },
    { name: "voice token for foreign channel", method: "POST", path: "", prefix: "voice", body: { channelId: "" } },
  ];

  for (const attack of attacks) {
    test(`${attack.name} → 403`, async () => {
      let path: string;
      let body = attack.body;
      switch (attack.prefix) {
        case "channel":
          path = `/api/channels/${bobChannel.id}${attack.path}`;
          if (attack.name.includes("pin")) body = { messageId: bobMessage };
          if (attack.name.includes("read")) body = { messageId: bobMessage };
          break;
        case "dm":
          path = `/api/dm/conversations/${bobDmId}${attack.path}`;
          break;
        case "message":
          path = `/api/messages/${bobMessage}${attack.path}`;
          break;
        case "voice":
          path = "/api/voice/token";
          body = { channelId: bobChannel.id };
          break;
        default:
          path = `/api/workspaces/${bobWs}${attack.path}`;
      }

      const res = await req(t, path, { method: attack.method, cookie: alice.cookie, body });
      expect(res.status).toBe(403);
      const text = await res.clone().text();
      expect(text).not.toContain("victim says hi");
      expect(text).not.toContain("private-ops");
      const f = await failure(res);
      expect(f.error).toBe("forbidden");
    });
  }

  test("alice cannot pull herself into bob's workspace via channel members", async () => {
    const res = await req(t, `/api/channels/${bobChannel.id}/members`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: alice.id },
    });
    expect(res.status).toBe(403);
    const rows = await t.db
      .select()
      .from(workspaceMembers)
      .where(eq(workspaceMembers.workspaceId, bobWs));
    expect(rows.some((m) => m.userId === alice.id)).toBe(false);
  });

  test("search does not leak foreign workspace content", async () => {
    const res = await req(t, "/api/search?q=victim", { cookie: alice.cookie });
    expect(res.status).toBe(200);
    const d = await data<{ messages: unknown[]; channels: unknown[]; people: unknown[] }>(res);
    expect(d.messages).toHaveLength(0);
    expect(d.channels).toHaveLength(0);
    expect(d.people).toHaveLength(0);
  });

  test("DM list never contains foreign conversations", async () => {
    const d = await data<{ conversations: Array<{ id: string }> }>(
      await req(t, "/api/dm/conversations", { cookie: alice.cookie }),
    );
    expect(d.conversations.map((c) => c.id)).not.toContain(bobDmId);
  });
});

describe("oversized payloads → 413", () => {
  test("real body above MAX_BODY_BYTES → 413", async () => {
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "x".repeat(5000) }, // > 4096 cap
    });
    expect(res.status).toBe(413);
    const f = await failure(res);
    expect(f.error).toContain("payload too large");
  });

  test("spoofed huge Content-Length with a tiny body → 413 (rejected before parsing)", async () => {
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "tiny" },
      headers: { "content-length": "99999999" },
    });
    expect(res.status).toBe(413);
  });

  test("oversized raw body (no help from zod) → 413 not 400", async () => {
    // must reach the body reader: target a channel the caller CAN access
    const ws = await makeWorkspace(t, alice.cookie, "Body Limit WS");
    const ch = await makeChannel(t, alice.cookie, ws.id, "body-limit-room");
    const res = await req(t, `/api/channels/${ch.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      rawBody: `{"content":"${"y".repeat(5000)}"}`,
    });
    expect(res.status).toBe(413);
  });
});

describe("identity spoofing is impossible", () => {
  test("author_id in the body never wins — checked in the DATABASE", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Spoof WS");
    const ch = await makeChannel(t, alice.cookie, ws.id, "spoof-room");

    const create = await req(t, `/api/channels/${ch.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "written by alice", authorId: bob.id, author_id: bob.id },
    });
    expect(create.status).toBe(201);
    const created = await data<{ message: { id: string; authorId: string } }>(create);
    expect(created.message.authorId).toBe(alice.id);

    const row = (
      await t.db.select().from(messages).where(eq(messages.id, created.message.id)).limit(1)
    )[0];
    expect(row?.authorId).toBe(alice.id); // ← persisted author, not the spoof

    const edit = await req(t, `/api/messages/${created.message.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { content: "still alice", authorId: bob.id, editedBy: bob.id },
    });
    expect(edit.status).toBe(200);
    const edited = await data<{ message: { authorId: string; editedAt: string | null } }>(edit);
    expect(edited.message.authorId).toBe(alice.id);
    expect(edited.message.editedAt).toBeTruthy();

    const reply = await req(t, `/api/messages/${created.message.id}/replies`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "reply by alice", authorId: bob.id },
    });
    expect(reply.status).toBe(201);
    expect((await data<{ reply: { authorId: string } }>(reply)).reply.authorId).toBe(alice.id);
  });

  test("voice token identity cannot be forged (always the session user)", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Voice Spoof WS");
    const ch = await makeChannel(t, alice.cookie, ws.id, "voice-room");
    const res = await req(t, "/api/voice/token", {
      method: "POST",
      cookie: alice.cookie,
      body: { channelId: ch.id, identity: bob.id, name: "Totally Bob" },
    });
    expect(res.status).toBe(200);
    const d = await data<{ token: string; identity: string }>(res);
    expect(d.identity).toBe(alice.id);
    expect(d.token).toContain(alice.id);
    expect(d.token).not.toContain(bob.id);
  });
});

describe("protocol-level protections", () => {
  test("a body stream that errors mid-read → 400 invalid JSON (not a crash)", async () => {
    const broken = new ReadableStream<Uint8Array>({
      pull() {
        throw new Error("stream exploded");
      },
    });
    const request = new Request("http://localhost:3000/api/workspaces", {
      method: "POST",
      headers: { "content-type": "application/json", cookie: alice.cookie },
      body: broken,
      duplex: "half",
    } as RequestInit & { duplex: "half" });

    const res = await t.app.request(request);
    expect(res.status).toBe(400);
    const f = await failure(res);
    expect(f.error).toContain("JSON");
  });

  test("malformed JSON body → 400 invalid JSON", async () => {
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      rawBody: "{not json at all",
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("invalid JSON");
  });

  test("tampered session cookie → 401", async () => {
    const fake = alice.cookie.replace(/session_token=[^;]+/, "session_token=tampered-value");
    const res = await req(t, "/api/workspaces", { cookie: fake });
    expect(res.status).toBe(401);
  });

  test("unknown route → 404 with {error,status} shape", async () => {
    const res = await req(t, "/api/definitely-not-a-route");
    expect(res.status).toBe(404);
    const f = await failure(res);
    expect(f.error).toBe("not found");
    expect(f.status).toBe(404);
  });

  test("x-request-id is generated and echoed on success AND failure", async () => {
    const okRes = await req(t, "/api/health");
    const okId = okRes.headers.get("x-request-id");
    expect(okId).toBeTruthy();
    expect(okId).not.toBe("health");

    const errRes = await req(t, "/api/workspaces");
    const errId = errRes.headers.get("x-request-id");
    expect(errId).toBeTruthy();
    expect(errId).not.toBe(okId); // fresh id per request
  });
});

describe("message-scoped access to private & DM channels", () => {
  test("workspace outsider cannot touch a private channel's message (403)", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Secret Notes");
    const priv = await makeChannel(t, alice.cookie, ws.id, "secret-notes", "private");
    const msg = await postMessage(t, alice.cookie, priv.id, "classified note");

    // bob: valid session, workspace NOT joined → 403 on every message route
    for (const [method, path, body] of [
      ["GET", `/api/messages/${msg.id}/replies`, undefined],
      ["POST", `/api/messages/${msg.id}/replies`, { content: "sneak" }],
      ["PATCH", `/api/messages/${msg.id}`, { content: "rewrite" }],
      ["DELETE", `/api/messages/${msg.id}`, undefined],
      ["PUT", `/api/messages/${msg.id}/reactions`, { emoji: "👀" }],
      ["DELETE", `/api/messages/${msg.id}/reactions`, { emoji: "👀" }],
    ] as const) {
      const res = await req(t, path, { method, cookie: bob.cookie, body });
      expect(res.status).toBe(403);
      const text = await res.clone().text();
      expect(text).not.toContain("classified note");
    }
  });

  test("workspace member OUTSIDE the private channel also gets 403", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Need To Know");
    await addMember(t, ws.id, bob.id, "member"); // workspace member…
    const priv = await makeChannel(t, alice.cookie, ws.id, "need-to-know", "private");
    const msg = await postMessage(t, alice.cookie, priv.id, "need to know info");

    const res = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "👍" },
    });
    expect(res.status).toBe(403); // …but not a channel member
  });

  test("private channel members CAN act on its messages", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Inner Circle");
    await addMember(t, ws.id, bob.id, "member"); // workspace member first…
    const priv = await makeChannel(t, alice.cookie, ws.id, "inner-circle", "private");
    const msg = await postMessage(t, alice.cookie, priv.id, "inner circle note");
    await req(t, `/api/channels/${priv.id}/members`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: bob.id },
    }); // …then admitted to the private channel

    const res = await req(t, `/api/messages/${msg.id}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "👍" },
    });
    expect(res.status).toBe(200);
  });

  test("DM participants can react to DM messages; outsiders cannot", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "DM Scope WS");
    await addMember(t, ws.id, bob.id, "member");
    await addMember(t, ws.id, carol.id, "member");

    const dm = await req(t, `/api/workspaces/${ws.id}/dm/conversations`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: bob.id },
    });
    const dmId = (await data<{ conversation: { id: string } }>(dm)).conversation.id;
    const sent = await req(t, `/api/dm/conversations/${dmId}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "between us" },
    });
    const dmMsgId = (await data<{ message: { id: string } }>(sent)).message.id;

    // participant (bob) → allowed
    const byMember = await req(t, `/api/messages/${dmMsgId}/reactions`, {
      method: "PUT",
      cookie: bob.cookie,
      body: { emoji: "❤️" },
    });
    expect(byMember.status).toBe(200);

    // workspace member but not a DM participant (carol) → 403
    const byOutsider = await req(t, `/api/messages/${dmMsgId}/reactions`, {
      method: "PUT",
      cookie: carol.cookie,
      body: { emoji: "❤️" },
    });
    expect(byOutsider.status).toBe(403);
  });
});

describe("CORS", () => {
  test("allowed origin gets CORS headers", async () => {
    const res = await req(t, "/api/health", { headers: { origin: "http://localhost:5173" } });
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:5173");
    expect(res.headers.get("access-control-allow-credentials")).toBe("true");
    expect(res.headers.get("vary")).toContain("Origin");
  });

  test("unknown origin is DENIED (403) with zero CORS headers", async () => {
    const res = await req(t, "/api/health", { headers: { origin: "https://evil.example.com" } });
    expect(res.status).toBe(403);
    const f = await failure(res);
    expect(f.error).toContain("origin");
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
    expect(res.headers.get("access-control-allow-credentials")).toBeNull();
  });

  test("preflight: allowed → 204 with allow headers; denied → 403", async () => {
    const allowed = await req(t, "/api/workspaces", {
      method: "OPTIONS",
      headers: {
        origin: "http://localhost:5173",
        "access-control-request-method": "POST",
        "access-control-request-headers": "content-type",
      },
    });
    expect(allowed.status).toBe(204);
    expect(allowed.headers.get("access-control-allow-methods")).toContain("POST");
    expect(allowed.headers.get("access-control-allow-origin")).toBe("http://localhost:5173");

    const denied = await req(t, "/api/workspaces", {
      method: "OPTIONS",
      headers: { origin: "https://evil.example.com", "access-control-request-method": "POST" },
    });
    expect(denied.status).toBe(403);
    expect(denied.headers.get("access-control-allow-origin")).toBeNull();
  });

  test("requests WITHOUT an Origin header are unaffected (server-to-server)", async () => {
    const res = await req(t, "/api/health");
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("pagination cursor helpers", () => {
  test("encode/decode round-trip; garbage and non-dates decode to null", async () => {
    const { encodeCursor, decodeCursor } = await import("../src/http");
    const when = new Date("2026-02-03T04:05:06.000Z");
    const cursor = encodeCursor(when, "36f0a2b1-c3d4-4e5f-8a9b-0c1d2e3f4a5b");
    const decoded = decodeCursor(cursor);
    expect(decoded?.t).toBe(when.toISOString());
    expect(decoded?.i).toBe("36f0a2b1-c3d4-4e5f-8a9b-0c1d2e3f4a5b");

    expect(decodeCursor("definitely not base64 json")).toBeNull();
    expect(decodeCursor("")).toBeNull();
    const notADate = Buffer.from(JSON.stringify({ t: "nope", i: "x" }), "utf8").toString(
      "base64url",
    );
    expect(decodeCursor(notADate)).toBeNull();
    const notAnObject = Buffer.from(JSON.stringify(["array"]), "utf8").toString("base64url");
    expect(decodeCursor(notAnObject)).toBeNull();
  });
});
