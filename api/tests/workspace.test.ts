/**
 * Workspace routes: creation, listing, detail, members, invites (create /
 * join-by-code / accept incl. expiry, reuse and email mismatch).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { eq } from "drizzle-orm";
import { invites } from "../src/db/schema";
import {
  addMember,
  createTestApp,
  data,
  failure,
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

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  carol = await signIn(t, uniqueEmail("carol"));
});
afterAll(async () => {
  await t?.close();
});

describe("POST /api/workspaces", () => {
  test("creates a workspace, derives a slug and makes the caller owner", async () => {
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "My Awesome Co!" },
    });
    expect(res.status).toBe(201);
    const d = await data<{ workspace: { id: string; slug: string; role: string; inviteCode: string } }>(res);
    expect(d.workspace.slug).toBe("my-awesome-co");
    expect(d.workspace.role).toBe("owner");
    expect(d.workspace.inviteCode).toHaveLength(8);

    const members = await data<{ members: Array<{ userId: string; role: string }> }>(
      await req(t, `/api/workspaces/${d.workspace.id}/members`, { cookie: alice.cookie }),
    );
    expect(members.members).toHaveLength(1);
    expect(members.members[0]?.role).toBe("owner");
    expect(members.members[0]?.userId).toBe(alice.id);
  });

  test("duplicate names get distinct slugs (auto suffix)", async () => {
    const a = await makeWorkspace(t, alice.cookie, "Duplicate Name Corp");
    const b = await makeWorkspace(t, alice.cookie, "Duplicate Name Corp");
    expect(a.slug).not.toBe(b.slug);
    expect(b.slug.startsWith("duplicate-name-corp")).toBe(true);
  });

  test("explicit slug with invalid characters → 400", async () => {
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "Valid", slug: "Not Valid!" },
    });
    expect(res.status).toBe(400);
    const f = await failure(res);
    expect(f.error).toContain("validation failed");
  });

  test("empty or oversized name → 400", async () => {
    const empty = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "   " },
    });
    expect(empty.status).toBe(400);
    const huge = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "x".repeat(81) },
    });
    expect(huge.status).toBe(400);
  });

  test("anonymous → 401", async () => {
    const res = await req(t, "/api/workspaces", { method: "POST", body: { name: "Nope" } });
    expect(res.status).toBe(401);
  });
});

describe("GET /api/workspaces + detail + members", () => {
  test("lists only my workspaces; invite code only for admin+", async () => {
    const mine = await makeWorkspace(t, alice.cookie, "Alice Only WS");
    await makeWorkspace(t, bob.cookie, "Bob Secret WS");

    const list = await data<{ workspaces: Array<{ id: string; inviteCode?: string; role: string }> }>(
      await req(t, "/api/workspaces", { cookie: alice.cookie }),
    );
    const ids = list.workspaces.map((w) => w.id);
    expect(ids).toContain(mine.id);

    const aliceOwned = list.workspaces.find((w) => w.id === mine.id);
    expect(aliceOwned?.role).toBe("owner");
    expect(aliceOwned?.inviteCode).toBeDefined();
  });

  test("plain member sees role=member and NO invite code", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Member View WS");
    await addMember(t, ws.id, carol.id, "member");

    const detail = await data<{ workspace: { role: string; inviteCode?: string } }>(
      await req(t, `/api/workspaces/${ws.id}`, { cookie: carol.cookie }),
    );
    expect(detail.workspace.role).toBe("member");
    expect(detail.workspace.inviteCode).toBeUndefined();

    const list = await data<{ workspaces: Array<{ id: string; inviteCode?: string }> }>(
      await req(t, "/api/workspaces", { cookie: carol.cookie }),
    );
    expect(list.workspaces.find((w) => w.id === ws.id)?.inviteCode).toBeUndefined();
  });

  test("members endpoint returns user info + roles", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Members WS");
    await addMember(t, ws.id, carol.id, "admin");

    const d = await data<{
      members: Array<{ userId: string; role: string; name: string; email: string }>;
    }>(await req(t, `/api/workspaces/${ws.id}/members`, { cookie: alice.cookie }));

    expect(d.members).toHaveLength(2);
    const carolRow = d.members.find((m) => m.userId === carol.id);
    expect(carolRow?.role).toBe("admin");
    expect(carolRow?.email).toBe(carol.email);
    expect(carolRow?.name).toBeTruthy();
  });
});

describe("invites", () => {
  test("member (non-admin) cannot create invites → 403", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Invite Guard WS");
    await addMember(t, ws.id, carol.id, "member");
    const res = await req(t, `/api/workspaces/${ws.id}/invites`, {
      method: "POST",
      cookie: carol.cookie,
      body: {},
    });
    expect(res.status).toBe(403);
  });

  test("admin creates an invite with accept URL; invitee accepts and joins", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Invite Flow WS");
    await addMember(t, ws.id, alice.id, "owner"); // already owner — idempotent setup

    const inviteRes = await req(t, `/api/workspaces/${ws.id}/invites`, {
      method: "POST",
      cookie: alice.cookie,
      body: { email: carol.email, expiresInHours: 24 },
    });
    expect(inviteRes.status).toBe(201);
    const { invite } = await data<{ invite: { token: string; acceptUrl: string; expiresAt: string } }>(inviteRes);
    expect(invite.acceptUrl).toContain(invite.token);
    expect(new Date(invite.expiresAt).getTime()).toBeGreaterThan(Date.now());

    const acceptRes = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: carol.cookie,
      body: { token: invite.token },
    });
    expect(acceptRes.status).toBe(200);
    const accepted = await data<{ workspaceId: string; alreadyMember: boolean }>(acceptRes);
    expect(accepted.workspaceId).toBe(ws.id);
    expect(accepted.alreadyMember).toBe(false);

    // reuse → 409
    const reuse = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: carol.cookie,
      body: { token: invite.token },
    });
    expect(reuse.status).toBe(409);
  });

  test("invite issued to another email → 403", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Email Bound WS");
    const inviteRes = await req(t, `/api/workspaces/${ws.id}/invites`, {
      method: "POST",
      cookie: alice.cookie,
      body: { email: "someone-else@example.com" },
    });
    const { invite } = await data<{ invite: { token: string } }>(inviteRes);

    const res = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: bob.cookie,
      body: { token: invite.token },
    });
    expect(res.status).toBe(403);
    const f = await failure(res);
    expect(f.error).toContain("different email");
  });

  test("expired invite → 400; unknown token → 400", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Expired WS");
    const inviteRes = await req(t, `/api/workspaces/${ws.id}/invites`, {
      method: "POST",
      cookie: alice.cookie,
      body: {},
    });
    const { invite } = await data<{ invite: { token: string; id: string } }>(inviteRes);

    // age it out directly (test setup)
    await t.db
      .update(invites)
      .set({ expiresAt: new Date(Date.now() - 1000) })
      .where(eq(invites.id, invite.id));

    const expired = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: bob.cookie,
      body: { token: invite.token },
    });
    expect(expired.status).toBe(400);
    expect((await failure(expired)).error).toContain("expired");

    const unknown = await req(t, "/api/invites/accept", {
      method: "POST",
      cookie: bob.cookie,
      body: { token: "z".repeat(43) },
    });
    expect(unknown.status).toBe(400);
  });
});

describe("POST /api/workspaces/:id/join (invite code)", () => {
  test("correct code joins (idempotent); wrong code → 400; anon → 401", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Code Join WS");

    const join = await req(t, `/api/workspaces/${ws.id}/join`, {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: ws.inviteCode.toLowerCase() },
    });
    expect(join.status).toBe(200);
    const joined = await data<{ alreadyMember: boolean }>(join);
    expect(joined.alreadyMember).toBe(false);

    const again = await req(t, `/api/workspaces/${ws.id}/join`, {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: ws.inviteCode },
    });
    expect(again.status).toBe(200);
    expect((await data<{ alreadyMember: boolean }>(again)).alreadyMember).toBe(true);

    const wrong = await req(t, `/api/workspaces/${ws.id}/join`, {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: "TOTALLYWRONG" },
    });
    expect(wrong.status).toBe(400);

    const anon = await req(t, `/api/workspaces/${ws.id}/join`, {
      method: "POST",
      body: { inviteCode: ws.inviteCode },
    });
    expect(anon.status).toBe(401);
  });

  test("malformed workspace id in path → 400", async () => {
    const res = await req(t, "/api/workspaces/definitely-not-a-uuid/join", {
      method: "POST",
      cookie: bob.cookie,
      body: { inviteCode: "ABCD" },
    });
    expect(res.status).toBe(400);
  });

  test("explicit slug that already exists → 409", async () => {
    await makeWorkspace(t, alice.cookie, "Slugged"); // slug: slugged
    const res = await req(t, "/api/workspaces", {
      method: "POST",
      cookie: alice.cookie,
      body: { name: "Different Name", slug: "slugged" },
    });
    expect(res.status).toBe(409);
    expect((await failure(res)).error).toContain("already exists");
  });
});

describe("Email + password auth (our own database)", () => {
  test("sign-up creates the account and returns a working session", async () => {
    const email = uniqueEmail("signup");
    const res = await req(t, "/api/auth/sign-up/email", {
      method: "POST",
      body: { email, password: "choose-a-good-password", name: "Sign Up" },
    });
    expect(res.status).toBe(200);
    const cookie = res.headers
      .getSetCookie()
      .find((c) => c.includes("session_token"))
      ?.split(";")[0];
    expect(cookie).toBeTruthy();

    const session = await req(t, "/api/auth/get-session", { cookie: cookie ?? "" });
    expect(session.status).toBe(200);
    expect(((await session.json()) as { user?: { email: string } }).user?.email).toBe(email);
  });

  test("sign-in rejects a wrong password with 401", async () => {
    const email = uniqueEmail("wrongpw");
    await req(t, "/api/auth/sign-up/email", {
      method: "POST",
      body: { email, password: "correct-password-1", name: "P" },
    });
    const res = await req(t, "/api/auth/sign-in/email", {
      method: "POST",
      body: { email, password: "not-the-password" },
    });
    expect(res.status).toBe(401);
  });

  test("sign-in accepts the right password and issues a session", async () => {
    const email = uniqueEmail("rightpw");
    await req(t, "/api/auth/sign-up/email", {
      method: "POST",
      body: { email, password: "correct-password-1", name: "P" },
    });
    const res = await req(t, "/api/auth/sign-in/email", {
      method: "POST",
      body: { email, password: "correct-password-1" },
    });
    expect(res.status).toBe(200);
    expect(
      res.headers.getSetCookie().some((c) => c.includes("session_token")),
    ).toBe(true);
  });

  test("passwords shorter than 8 characters are rejected", async () => {
    const res = await req(t, "/api/auth/sign-up/email", {
      method: "POST",
      body: { email: uniqueEmail("short"), password: "short", name: "S" },
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});
