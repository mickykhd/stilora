/**
 * THE 4-way auth matrix — applied to EVERY non-health endpoint.
 *
 *   1. valid session + workspace/channel member → 2xx with correct data
 *   2. no session (anonymous)                   → 401 {error:"unauthorized"}
 *   3. valid session but NOT a member           → 403 {error:"forbidden"}
 *      (unscoped routes instead prove data isolation: no foreign ids leak)
 *   4. malformed ids / invalid payloads / bad tokens → 4xx;
 *      repeated violations → 429 with Retry-After (asserted at the bottom)
 *
 * Invite credential routes (join / invites/accept) are intentionally reachable
 * by valid non-members — the credential IS the authorization — so their case 3
 * asserts the documented exception plus full invalid-credential rejection.
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
  type WorkspaceFixture,
} from "./helpers";

let t: TestApp;
let rateApp: TestApp;
let alice: SignedInUser;
let bob: SignedInUser;
let carol: SignedInUser;
let wsA: WorkspaceFixture;
let wsB: WorkspaceFixture;
let channelA: { id: string };
let dmChannelId: string;
let seq = 0;

const unique = (prefix: string): string => `${prefix}-${(seq += 1)}`;

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  carol = await signIn(t, uniqueEmail("carol"));

  wsA = await makeWorkspace(t, alice.cookie, "Matrix Workspace");
  wsB = await makeWorkspace(t, carol.cookie, "Matrix Workspace B");
  await addMember(t, wsA.id, carol.id, "member");

  channelA = await makeChannel(t, alice.cookie, wsA.id, "general");

  const dmRes = await req(t, `/api/workspaces/${wsA.id}/dm/conversations`, {
    method: "POST",
    cookie: alice.cookie,
    body: { userId: carol.id },
  });
  dmChannelId = (await data<{ conversation: { id: string } }>(dmRes)).conversation.id;

  // tiny limits for the 429 leg of the matrix
  rateApp = await createTestApp({
    RATE_LIMIT_ROUTE_PER_MIN: "5",
    RATE_LIMIT_GLOBAL_PER_MIN: "1000",
  });
});

afterAll(async () => {
  await t?.close();
  await rateApp?.close();
});

interface RouteSpec {
  name: string;
  method: string;
  /** Path+body used by BOTH the member and the non-member case. */
  build: () => { path: string; body?: unknown };
  /** Statuses accepted for the authorized member (2xx range by default). */
  memberStatus?: number[];
  /** Unscoped routes: non-members may call them — assert data isolation. */
  unscoped?: boolean;
  isolation?: (res: Response) => Promise<void>;
  /** Case 4 shape: how the invalid request is constructed.
   *  `path` may be a thunk — the routes array is built before fixtures exist. */
  invalid: { kind: "path" | "body" | "query" | "token"; path?: string | (() => string); body?: unknown };
}

async function freshMessage(): Promise<string> {
  return (await postMessage(t, alice.cookie, channelA.id, `matrix ${unique("msg")}`)).id;
}

const routes: RouteSpec[] = [
  // ---- workspace-scoped ----------------------------------------------------
  {
    name: "GET /api/workspaces/:workspaceId",
    method: "GET",
    build: () => ({ path: `/api/workspaces/${wsA.id}` }),
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid" },
  },
  {
    name: "GET /api/workspaces/:workspaceId/members",
    method: "GET",
    build: () => ({ path: `/api/workspaces/${wsA.id}/members` }),
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid/members" },
  },
  {
    name: "POST /api/workspaces/:workspaceId/invites",
    method: "POST",
    build: () => ({ path: `/api/workspaces/${wsA.id}/invites`, body: { email: "x@example.com" } }),
    memberStatus: [201],
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid/invites", body: {} },
  },
  {
    name: "GET /api/workspaces/:workspaceId/channels",
    method: "GET",
    build: () => ({ path: `/api/workspaces/${wsA.id}/channels` }),
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid/channels" },
  },
  {
    name: "POST /api/workspaces/:workspaceId/channels",
    method: "POST",
    build: () => ({
      path: `/api/workspaces/${wsA.id}/channels`,
      body: { name: unique("chan") },
    }),
    memberStatus: [201],
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid/channels", body: { name: "x" } },
  },
  {
    name: "POST /api/workspaces/:workspaceId/dm/conversations",
    method: "POST",
    build: () => ({
      path: `/api/workspaces/${wsA.id}/dm/conversations`,
      body: { userId: carol.id },
    }),
    memberStatus: [200, 201],
    invalid: { kind: "path", path: "/api/workspaces/not-a-uuid/dm/conversations", body: {} },
  },

  // ---- channel-scoped ------------------------------------------------------
  {
    name: "GET /api/channels/:channelId",
    method: "GET",
    build: () => ({ path: `/api/channels/${channelA.id}` }),
    invalid: { kind: "path", path: "/api/channels/not-a-uuid" },
  },
  {
    name: "PATCH /api/channels/:channelId",
    method: "PATCH",
    build: () => ({ path: `/api/channels/${channelA.id}`, body: { topic: unique("topic") } }),
    invalid: { kind: "path", path: "/api/channels/not-a-uuid", body: { topic: "x" } },
  },
  {
    name: "POST /api/channels/:channelId/members",
    method: "POST",
    build: () => ({ path: `/api/channels/${channelA.id}/members`, body: { userId: carol.id } }),
    memberStatus: [200, 201],
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/members", body: {} },
  },
  {
    name: "POST /api/channels/:channelId/read",
    method: "POST",
    build: () => ({ path: `/api/channels/${channelA.id}/read` }), // body resolved in test
    memberStatus: [200],
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/read", body: {} },
  },
  {
    name: "GET /api/channels/:channelId/messages",
    method: "GET",
    build: () => ({ path: `/api/channels/${channelA.id}/messages` }),
    invalid: { kind: "query", path: () => `/api/channels/${channelA.id}/messages?limit=abc` },
  },
  {
    name: "POST /api/channels/:channelId/messages",
    method: "POST",
    build: () => ({
      path: `/api/channels/${channelA.id}/messages`,
      body: { content: unique("hello") },
    }),
    memberStatus: [201],
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/messages", body: { content: "x" } },
  },
  {
    name: "GET /api/channels/:channelId/pins",
    method: "GET",
    build: () => ({ path: `/api/channels/${channelA.id}/pins` }),
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/pins" },
  },
  {
    name: "POST /api/channels/:channelId/pins",
    method: "POST",
    build: () => ({ path: `/api/channels/${channelA.id}/pins` }), // body resolved in test
    memberStatus: [200, 201],
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/pins", body: {} },
  },
  {
    name: "DELETE /api/channels/:channelId/pins",
    method: "DELETE",
    build: () => ({ path: `/api/channels/${channelA.id}/pins` }), // body resolved in test
    memberStatus: [200],
    invalid: { kind: "path", path: "/api/channels/not-a-uuid/pins", body: {} },
  },

  // ---- dm-scoped -----------------------------------------------------------
  {
    name: "GET /api/dm/conversations/:channelId/messages",
    method: "GET",
    build: () => ({ path: `/api/dm/conversations/${dmChannelId}/messages` }),
    invalid: { kind: "path", path: "/api/dm/conversations/not-a-uuid/messages" },
  },
  {
    name: "POST /api/dm/conversations/:channelId/messages",
    method: "POST",
    build: () => ({
      path: `/api/dm/conversations/${dmChannelId}/messages`,
      body: { content: unique("dm") },
    }),
    memberStatus: [201],
    invalid: { kind: "path", path: "/api/dm/conversations/not-a-uuid/messages", body: { content: "x" } },
  },

  // ---- voice (body/query-scoped channel) -----------------------------------
  {
    name: "POST /api/voice/token",
    method: "POST",
    build: () => ({ path: "/api/voice/token", body: { channelId: channelA.id } }),
    invalid: { kind: "body", path: "/api/voice/token", body: { channelId: "not-a-uuid" } },
  },
  {
    name: "GET /api/voice/state",
    method: "GET",
    build: () => ({ path: `/api/voice/state?channelId=${channelA.id}` }),
    invalid: { kind: "query", path: "/api/voice/state?channelId=not-a-uuid" },
  },

  // ---- message-scoped ------------------------------------------------------
  {
    name: "PATCH /api/messages/:messageId",
    method: "PATCH",
    build: () => ({ path: "" }), // body resolved in test (fresh message)
    invalid: { kind: "path", path: "/api/messages/not-a-uuid", body: { content: "x" } },
  },
  {
    name: "DELETE /api/messages/:messageId",
    method: "DELETE",
    build: () => ({ path: "" }),
    invalid: { kind: "path", path: "/api/messages/not-a-uuid" },
  },
  {
    name: "GET /api/messages/:messageId/replies",
    method: "GET",
    build: () => ({ path: "" }),
    invalid: { kind: "path", path: "/api/messages/not-a-uuid/replies" },
  },
  {
    name: "POST /api/messages/:messageId/replies",
    method: "POST",
    build: () => ({ path: "" }),
    memberStatus: [201],
    invalid: { kind: "path", path: "/api/messages/not-a-uuid/replies", body: { content: "x" } },
  },
  {
    name: "PUT /api/messages/:messageId/reactions",
    method: "PUT",
    build: () => ({ path: "" }),
    invalid: { kind: "path", path: "/api/messages/not-a-uuid/reactions", body: { emoji: "👍" } },
  },
  {
    name: "DELETE /api/messages/:messageId/reactions",
    method: "DELETE",
    build: () => ({ path: "" }),
    invalid: { kind: "path", path: "/api/messages/not-a-uuid/reactions", body: { emoji: "👍" } },
  },

  // ---- unscoped ------------------------------------------------------------
  {
    name: "GET /api/workspaces",
    method: "GET",
    build: () => ({ path: "/api/workspaces" }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ workspaces: Array<{ id: string }> }>(res);
      expect(d.workspaces.map((w) => w.id)).not.toContain(wsA.id);
    },
    invalid: { kind: "token", path: "/api/workspaces" },
  },
  {
    name: "POST /api/workspaces",
    method: "POST",
    build: () => ({ path: "/api/workspaces", body: { name: unique("Solo") } }),
    memberStatus: [201],
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ workspace: { id: string } }>(res);
      expect(d.workspace.id).not.toBe(wsA.id); // brand-new, nothing foreign
    },
    invalid: { kind: "body", path: "/api/workspaces", body: {} },
  },
  {
    name: "GET /api/search",
    method: "GET",
    build: () => ({ path: `/api/search?q=${unique("qword")}` }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ messages: unknown[]; channels: unknown[]; people: unknown[] }>(res);
      expect(d.messages).toHaveLength(0);
      expect(d.channels).toHaveLength(0);
      expect(d.people).toHaveLength(0);
    },
    invalid: { kind: "query", path: "/api/search" },
  },
  {
    name: "GET /api/notifications",
    method: "GET",
    build: () => ({ path: "/api/notifications" }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ notifications: unknown[] }>(res);
      expect(Array.isArray(d.notifications)).toBe(true);
    },
    invalid: { kind: "query", path: "/api/notifications?cursor=%%%garbage%%%" },
  },
  {
    name: "POST /api/notifications/read",
    method: "POST",
    build: () => ({ path: "/api/notifications/read", body: {} }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ updated: number }>(res);
      expect(d.updated).toBeGreaterThanOrEqual(0);
    },
    invalid: { kind: "body", path: "/api/notifications/read", body: { ids: ["not-a-uuid"] } },
  },
  {
    name: "GET /api/notifications/prefs",
    method: "GET",
    build: () => ({ path: "/api/notifications/prefs" }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ prefs: { deepWorkEnabled: boolean } }>(res);
      expect(typeof d.prefs.deepWorkEnabled).toBe("boolean");
    },
    invalid: { kind: "token", path: "/api/notifications/prefs" },
  },
  {
    name: "PUT /api/notifications/prefs",
    method: "PUT",
    build: () => ({ path: "/api/notifications/prefs", body: { deepWorkEnabled: true } }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ prefs: { deepWorkEnabled: boolean } }>(res);
      expect(d.prefs.deepWorkEnabled).toBe(true);
    },
    invalid: { kind: "body", path: "/api/notifications/prefs", body: {} },
  },
  {
    name: "POST /api/uploads/sign",
    method: "POST",
    build: () => ({
      path: "/api/uploads/sign",
      body: { fileName: "a.png", contentType: "image/png", sizeBytes: 128 },
    }),
    memberStatus: [201],
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ upload: { key: string } }>(res);
      expect(d.upload.key).toContain("uploads/"); // scoped to the caller's own folder
    },
    invalid: { kind: "body", path: "/api/uploads/sign", body: {} },
  },
  {
    name: "GET /api/dm/conversations",
    method: "GET",
    build: () => ({ path: "/api/dm/conversations" }),
    unscoped: true,
    isolation: async (res) => {
      const d = await data<{ conversations: Array<{ id: string }> }>(res);
      expect(d.conversations.map((c) => c.id)).not.toContain(dmChannelId);
    },
    invalid: { kind: "token", path: "/api/dm/conversations" },
  },
];

/** Routes whose `build()` needs a message id created at call time. */
async function buildWithMessage(spec: RouteSpec): Promise<{ path: string; body?: unknown }> {
  if (spec.name.includes("reactions")) {
    return { path: `/api/messages/${await freshMessage()}/reactions`, body: { emoji: "👍" } };
  }
  if (spec.name.includes("channelId/read")) {
    return { path: `/api/channels/${channelA.id}/read`, body: { messageId: await freshMessage() } };
  }
  if (spec.name.startsWith("POST /api/channels/:channelId/pins")) {
    return { path: `/api/channels/${channelA.id}/pins`, body: { messageId: await freshMessage() } };
  }
  if (spec.name.startsWith("DELETE /api/channels/:channelId/pins")) {
    return { path: `/api/channels/${channelA.id}/pins`, body: { messageId: await freshMessage() } };
  }
  if (spec.name.startsWith("PATCH /api/messages")) {
    return { path: `/api/messages/${await freshMessage()}`, body: { content: "edited in matrix" } };
  }
  if (spec.name.startsWith("DELETE /api/messages")) {
    return { path: `/api/messages/${await freshMessage()}` };
  }
  if (spec.name.startsWith("GET /api/messages")) {
    return { path: `/api/messages/${await freshMessage()}/replies` };
  }
  if (spec.name.startsWith("POST /api/messages")) {
    return { path: `/api/messages/${await freshMessage()}/replies`, body: { content: "matrix reply" } };
  }
  return spec.build();
}

describe("4-way auth matrix (every non-health endpoint)", () => {
  for (const spec of routes) {
    const expectedMember = spec.memberStatus ?? [200];

    test(`1 · member → 2xx · ${spec.name}`, async () => {
      const { path, body } = await buildWithMessage(spec);
      const res = await req(t, path, { method: spec.method, cookie: alice.cookie, body });
      expect(expectedMember).toContain(res.status);
      // response must carry data (not an error envelope)
      const parsed = (await res.clone().json()) as { data?: unknown; error?: string };
      expect(parsed.error).toBeUndefined();
      expect(parsed.data).toBeDefined();
    });

    test(`2 · anonymous → 401 · ${spec.name}`, async () => {
      const { path, body } = await buildWithMessage(spec);
      const res = await req(t, path, { method: spec.method, body });
      expect(res.status).toBe(401);
      const f = await failure(res);
      expect(f.error).toBe("unauthorized");
    });

    if (spec.unscoped) {
      test(`3 · non-member scoped-out (data isolation) · ${spec.name}`, async () => {
        const { path, body } = await buildWithMessage(spec);
        const res = await req(t, path, { method: spec.method, cookie: bob.cookie, body });
        expect(res.status).toBeLessThan(300);
        if (spec.isolation) await spec.isolation(res);
      });
    } else {
      test(`3 · non-member → 403 · ${spec.name}`, async () => {
        const { path, body } = await buildWithMessage(spec);
        const res = await req(t, path, { method: spec.method, cookie: bob.cookie, body });
        expect(res.status).toBe(403);
        // zero leakage: no workspace/channel ids in the response body
        const text = await res.clone().text();
        expect(text).not.toContain(wsA.id);
        expect(text).not.toContain(channelA.id);
        const f = await failure(res);
        expect(f.error).toBe("forbidden");
      });
    }

    test(`4 · invalid input → 4xx · ${spec.name}`, async () => {
      const inv = spec.invalid;
      const invPath = typeof inv.path === "function" ? inv.path() : (inv.path ?? "/");
      const res = await req(t, invPath, {
        method: spec.method,
        cookie: inv.kind === "token" ? "better-auth.session_token=bogus" : alice.cookie,
        body: inv.kind === "token" ? undefined : inv.body,
      });
      expect(res.status).toBeGreaterThanOrEqual(400);
      expect(res.status).toBeLessThan(500);
      const f = await failure(res);
      expect(f.status).toBe(res.status);
    });
  }
});

describe("credential-based joins (documented matrix exception)", () => {
  test("valid invite code: non-member may join; bad code rejected", async () => {
    const okRes = await req(t, `/api/workspaces/${wsB.id}/join`, {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: wsB.inviteCode },
    });
    expect(okRes.status).toBe(200);

    const badRes = await req(t, `/api/workspaces/${wsB.id}/join`, {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: "WRONGCODE123" },
    });
    expect(badRes.status).toBe(400);
  });

  test("valid invite token: non-member may accept; invalid token rejected; anon 401", async () => {
    const inviteRes = await req(t, `/api/workspaces/${wsB.id}/invites`, {
      method: "POST",
      cookie: carol.cookie,
      body: {},
    });
    expect(inviteRes.status).toBe(201);
    const { invite } = await data<{ invite: { token: string } }>(inviteRes);

    const acceptRes = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: bob.cookie,
      body: { token: invite.token },
    });
    expect(acceptRes.status).toBe(200);

    const badRes = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: bob.cookie,
      body: { token: "x".repeat(32) },
    });
    expect(badRes.status).toBe(400);

    const anonRes = await req(t, "/api/invites/accept", {
      method: "POST",
      body: { token: invite.token },
    });
    expect(anonRes.status).toBe(401);
    expect((await failure(anonRes)).error).toBe("unauthorized");
  });
});

describe("repeated violations → 429", () => {
  test("hammering a route with a malformed token eventually returns 429 + Retry-After", async () => {
    let saw429 = false;
    let retryAfter: string | null = null;
    for (let i = 0; i < 8; i++) {
      const res = await req(rateApp, "/api/workspaces", {
        cookie: "better-auth.session_token=definitely-not-a-token",
        ip: "203.0.113.9",
      });
      if (res.status === 429) {
        saw429 = true;
        retryAfter = res.headers.get("retry-after");
        break;
      }
      expect(res.status).toBe(401); // malformed token → 4xx until the limit hits
    }
    expect(saw429).toBe(true);
    expect(retryAfter).not.toBeNull();
    expect(Number(retryAfter)).toBeGreaterThanOrEqual(1);
  });
});
