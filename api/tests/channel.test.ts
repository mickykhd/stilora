/**
 * Channel routes: creation/validation, duplicate names, private-channel
 * visibility, role-gated updates, membership, read state, archived guard.
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
let alice: SignedInUser; // owner
let erin: SignedInUser; // plain member
let mallory: SignedInUser; // outsider
let wsId: string;

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  erin = await signIn(t, uniqueEmail("erin"));
  mallory = await signIn(t, uniqueEmail("mallory"));
  const ws = await makeWorkspace(t, alice.cookie, "Channel WS");
  wsId = ws.id;
  await addMember(t, wsId, erin.id, "member");
});
afterAll(async () => {
  await t?.close();
});

describe("channel creation", () => {
  test("creates a public channel; creator is joined; visible to workspace members", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "general");
    expect(ch.name).toBe("general");

    // the creator holds a membership row (read-state tracking starts immediately)
    const listAsCreator = await data<{ channels: Array<{ id: string; joined: boolean; kind: string }> }>(
      await req(t, `/api/workspaces/${wsId}/channels`, { cookie: alice.cookie }),
    );
    const asCreator = listAsCreator.channels.find((c) => c.id === ch.id);
    expect(asCreator?.kind).toBe("public");
    expect(asCreator?.joined).toBe(true);

    // other workspace members see the public channel (not yet joined themselves)
    const list = await data<{ channels: Array<{ id: string; joined: boolean; kind: string }> }>(
      await req(t, `/api/workspaces/${wsId}/channels`, { cookie: erin.cookie }),
    );
    const found = list.channels.find((c) => c.id === ch.id);
    expect(found).toBeDefined();
    expect(found?.kind).toBe("public");
    expect(found?.joined).toBe(false);
  });

  test("duplicate channel name → 409", async () => {
    await makeChannel(t, alice.cookie, wsId, "dupes");
    const res = await req(t, `/api/workspaces/${wsId}/channels`, {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "dupes" },
    });
    expect(res.status).toBe(409);
    expect((await failure(res)).error).toContain("already exists");
  });

  test("invalid names / dm kind rejected → 400", async () => {
    for (const name of ["Has Space", "UPPER", "-leading", "bad/slash"]) {
      const res = await req(t, `/api/workspaces/${wsId}/channels`, {
        method: "POST",
        cookie: alice.cookie,
        body: { name },
      });
      expect(res.status).toBe(400);
    }
    const dm = await req(t, `/api/workspaces/${wsId}/channels`, {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "sneaky", kind: "dm" },
    });
    expect(dm.status).toBe(400);
  });
});

describe("private channels", () => {
  test("invisible to non-members of the channel; creator can add members", async () => {
    const createRes = await req(t, `/api/workspaces/${wsId}/channels`, {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "leadership", kind: "private", topic: "secret plans" },
    });
    expect(createRes.status).toBe(201);
    const { channel: privChannel } = await data<{ channel: { id: string } }>(createRes);
    const privId = privChannel.id;

    // workspace member without channel membership: hidden + 403
    const listAsErin = await data<{ channels: Array<{ id: string }> }>(
      await req(t, `/api/workspaces/${wsId}/channels`, { cookie: erin.cookie }),
    );
    expect(listAsErin.channels.map((c) => c.id)).not.toContain(privId);
    const getAsErin = await req(t, `/api/channels/${privId}`, { cookie: erin.cookie });
    expect(getAsErin.status).toBe(403);

    // outsider gets 403 too
    const getAsMallory = await req(t, `/api/channels/${privId}`, { cookie: mallory.cookie });
    expect(getAsMallory.status).toBe(403);

    // creator adds erin → now visible
    const add = await req(t, `/api/channels/${privId}/members`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: erin.id },
    });
    expect(add.status).toBe(201);
    const getAfter = await req(t, `/api/channels/${privId}`, { cookie: erin.cookie });
    expect(getAfter.status).toBe(200);
  });

  test("adding a non-workspace user → 400", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "guard-private", "private");
    const res = await req(t, `/api/channels/${ch.id}/members`, {
      method: "POST",
      cookie: alice.cookie,
      body: { userId: mallory.id },
    });
    expect(res.status).toBe(400);
    expect((await failure(res)).error).toContain("not a member of this workspace");
  });

  test("plain member cannot add other members → 403", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "guard-private-2", "private");
    const res = await req(t, `/api/channels/${ch.id}/members`, {
      method: "POST",
      cookie: erin.cookie,
      body: { userId: erin.id },
    });
    expect(res.status).toBe(403);
  });
});

describe("PATCH /api/channels/:channelId", () => {
  test("creator renames + archives; member forbidden; empty patch → 400", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "editable");

    const okRes = await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { topic: "all about editing", archived: true },
    });
    expect(okRes.status).toBe(200);
    const d = await data<{ channel: { topic: string; archived: boolean } }>(okRes);
    expect(d.channel.topic).toBe("all about editing");
    expect(d.channel.archived).toBe(true);

    const forbidden = await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: erin.cookie,
      body: { topic: "hijack" },
    });
    expect(forbidden.status).toBe(403);

    const empty = await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: {},
    });
    expect(empty.status).toBe(400);
  });

  test("rename onto an existing channel name → 409", async () => {
    await makeChannel(t, alice.cookie, wsId, "taken-name");
    const ch = await makeChannel(t, alice.cookie, wsId, "rename-me");
    const res = await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { name: "taken-name" },
    });
    expect(res.status).toBe(409);
  });

  test("workspace admin (not creator) may update someone else's channel", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Admin Patch WS");
    const adminUser = await signIn(t, uniqueEmail("admin"));
    await addMember(t, ws.id, adminUser.id, "admin");
    const ch = await makeChannel(t, alice.cookie, ws.id, "theirs");

    const res = await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: adminUser.cookie,
      body: { topic: "admin took over" },
    });
    expect(res.status).toBe(200);
  });
});

describe("archived channels", () => {
  test("posting into an archived channel → 400; reads still work", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "old-times");
    await req(t, `/api/channels/${ch.id}`, {
      method: "PATCH",
      cookie: alice.cookie,
      body: { archived: true },
    });

    const post = await req(t, `/api/channels/${ch.id}/messages`, {
      method: "POST",
      cookie: alice.cookie,
      body: { content: "hello?" },
    });
    expect(post.status).toBe(400);
    expect((await failure(post)).error).toContain("archived");

    const read = await req(t, `/api/channels/${ch.id}/messages`, { cookie: alice.cookie });
    expect(read.status).toBe(200);
  });
});

describe("POST /api/channels/:channelId/read", () => {
  test("stores lastReadMessageId; foreign message id → 404", async () => {
    const ch = await makeChannel(t, alice.cookie, wsId, "read-marker");
    const msg = await postMessage(t, alice.cookie, ch.id, "read me");

    const res = await req(t, `/api/channels/${ch.id}/read`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: msg.id },
    });
    expect(res.status).toBe(200);
    expect((await data<{ lastReadMessageId: string }>(res)).lastReadMessageId).toBe(msg.id);

    const detail = await data<{ channel: { lastReadMessageId: string | null } }>(
      await req(t, `/api/channels/${ch.id}`, { cookie: alice.cookie }),
    );
    expect(detail.channel.lastReadMessageId).toBe(msg.id);

    const otherCh = await makeChannel(t, alice.cookie, wsId, "elsewhere");
    const foreign = await req(t, `/api/channels/${ch.id}/read`, {
      method: "POST",
      cookie: alice.cookie,
      body: { messageId: (await postMessage(t, alice.cookie, otherCh.id, "other")).id },
    });
    expect(foreign.status).toBe(404);
  });
});
