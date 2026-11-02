/**
 * Search: Postgres full-text over messages, ILIKE over channels/people —
 * with hard cross-workspace isolation (exact-match fixtures, no network).
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
let carol: SignedInUser;
let aliceWs: string;
let bobWs: string;
let aliceChannel: { id: string };
let bobChannel: { id: string };

interface SearchBody {
  query: string;
  scope: string;
  messages: Array<{ id: string; content: string; channelId: string }>;
  channels: Array<{ id: string; name: string | null }>;
  people: Array<{ id: string; name: string; email: string }>;
}

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"), "Alice Searcher");
  bob = await signIn(t, uniqueEmail("bob"), "Bob Insulator");
  carol = await signIn(t, uniqueEmail("carol"), "Carol Neutral");

  const aws = await makeWorkspace(t, alice.cookie, "Searchable WS");
  aliceWs = aws.id;
  aliceChannel = await makeChannel(t, alice.cookie, aliceWs, "general");
  await postMessage(t, alice.cookie, aliceChannel.id, "the quick brown fox jumps over");
  await postMessage(t, alice.cookie, aliceChannel.id, "completely unrelated content");

  const bws = await makeWorkspace(t, bob.cookie, "Private Fox WS");
  bobWs = bws.id;
  bobChannel = await makeChannel(t, bob.cookie, bobWs, "secret-fox-den");
  await postMessage(t, bob.cookie, bobChannel.id, "another fox hides in this burrow");
});
afterAll(async () => {
  await t?.close();
});

describe("GET /api/search — messages (full-text tsquery)", () => {
  test("exact word match finds my message only — never another workspace's", async () => {
    const res = await req(t, "/api/search?q=fox", { cookie: alice.cookie });
    expect(res.status).toBe(200);
    const d = await data<SearchBody>(res);

    expect(d.messages).toHaveLength(1);
    expect(d.messages[0]?.content).toContain("brown fox");
    expect(d.messages[0]?.channelId).toBe(aliceChannel.id);
    // bob's "fox" message must NOT leak across workspaces
    const ids = d.messages.map((m) => m.id);
    expect(ids.join()).not.toContain("burrow");
    expect(d.messages.some((m) => m.content.includes("burrow"))).toBe(false);
  });

  test("no match → empty groups", async () => {
    const d = await data<SearchBody>(await req(t, "/api/search?q=zebracorn", { cookie: alice.cookie }));
    expect(d.messages).toHaveLength(0);
    expect(d.channels).toHaveLength(0);
    expect(d.people).toHaveLength(0);
  });

  test("deleted messages are not searchable", async () => {
    const doomed = await postMessage(t, alice.cookie, aliceChannel.id, "kangaroos are temporary");
    await req(t, `/api/messages/${doomed.id}`, { method: "DELETE", cookie: alice.cookie });

    const d = await data<SearchBody>(
      await req(t, "/api/search?q=kangaroos", { cookie: alice.cookie }),
    );
    expect(d.messages).toHaveLength(0);
  });

  test("outsider searching my exact terms sees nothing", async () => {
    const d = await data<SearchBody>(await req(t, "/api/search?q=brown", { cookie: bob.cookie }));
    expect(d.messages).toHaveLength(0);
    expect(d.channels).toHaveLength(0);
  });
});

describe("GET /api/search — channels & people", () => {
  test("channel name matches are scoped to my workspaces", async () => {
    const mine = await data<SearchBody>(await req(t, "/api/search?q=general", { cookie: alice.cookie }));
    expect(mine.channels.map((c) => c.name)).toContain("general");

    const foreign = await data<SearchBody>(
      await req(t, "/api/search?q=secret-fox-den", { cookie: alice.cookie }),
    );
    expect(foreign.channels).toHaveLength(0);
  });

  test("people search only returns users sharing a workspace with me", async () => {
    const d = await data<SearchBody>(await req(t, "/api/search?q=Searcher", { cookie: alice.cookie }));
    expect(d.people).toHaveLength(1);
    expect(d.people[0]?.name).toBe("Alice Searcher");

    const outsider = await data<SearchBody>(
      await req(t, "/api/search?q=Insulator", { cookie: alice.cookie }),
    );
    expect(outsider.people).toHaveLength(0); // bob shares no workspace with alice

    // carol (member of alice's ws) can be found by alice
    await addMember(t, aliceWs, carol.id, "member");
    const carolRes = await data<SearchBody>(
      await req(t, "/api/search?q=Neutral", { cookie: alice.cookie }),
    );
    expect(carolRes.people.map((p) => p.name)).toContain("Carol Neutral");
  });
});

describe("GET /api/search — scopes & validation", () => {
  test("scope=messages returns only the messages group", async () => {
    const d = await data<SearchBody>(
      await req(t, "/api/search?q=fox&scope=messages", { cookie: alice.cookie }),
    );
    expect(d.scope).toBe("messages");
    expect(d.messages.length).toBeGreaterThan(0);
    expect(d.channels).toHaveLength(0);
    expect(d.people).toHaveLength(0);
  });

  test("scope=people returns only people", async () => {
    const d = await data<SearchBody>(
      await req(t, "/api/search?q=Searcher&scope=people", { cookie: alice.cookie }),
    );
    expect(d.people.length).toBeGreaterThan(0);
    expect(d.messages).toHaveLength(0);
    expect(d.channels).toHaveLength(0);
  });

  test("missing q / invalid scope / oversized q → 400", async () => {
    expect((await req(t, "/api/search", { cookie: alice.cookie })).status).toBe(400);
    expect(
      (await req(t, "/api/search?q=hi&scope=everything", { cookie: alice.cookie })).status,
    ).toBe(400);
    expect(
      (await req(t, `/api/search?q=${"x".repeat(101)}`, { cookie: alice.cookie })).status,
    ).toBe(400);
  });

  test("anonymous → 401", async () => {
    const res = await req(t, "/api/search?q=fox");
    expect(res.status).toBe(401);
    expect((await failure(res)).error).toBe("unauthorized");
  });
});
