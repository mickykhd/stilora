/**
 * Notification routes: activity feed + cursor pagination, mark-read,
 * deep-work preferences (incl. cross-midnight windows and the delivery-hold
 * behavior wired into recordActivity).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  addMember,
  createTestApp,
  data,
  makeWorkspace,
  req,
  signIn,
  uniqueEmail,
  type SignedInUser,
  type TestApp,
} from "./helpers";
import { isInDeepWorkWindow } from "../src/services/activity";

let t: TestApp;
let alice: SignedInUser;
let bob: SignedInUser;
let wsId: string;
let dmId: string;

function hhmm(d: Date): string {
  return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
}

async function bobSendsDm(content: string): Promise<void> {
  const res = await req(t, `/api/dm/conversations/${dmId}/messages`, {
    method: "POST",
    cookie: bob.cookie,
    body: { content },
  });
  if (res.status !== 201) throw new Error(`dm send failed: ${res.status}`);
}

beforeAll(async () => {
  t = await createTestApp();
  alice = await signIn(t, uniqueEmail("alice"));
  bob = await signIn(t, uniqueEmail("bob"));
  const ws = await makeWorkspace(t, alice.cookie, "Notif WS");
  wsId = ws.id;
  await addMember(t, wsId, bob.id, "member");

  const dm = await req(t, `/api/workspaces/${wsId}/dm/conversations`, {
    method: "POST",
    cookie: alice.cookie,
    body: { userId: bob.id },
  });
  dmId = (await data<{ conversation: { id: string } }>(dm)).conversation.id;
});
afterAll(async () => {
  await t?.close();
});

interface FeedBody {
  notifications: Array<{ id: string; type: string; payload: unknown; readAt: string | null }>;
  unreadCount: number;
  nextCursor: string | null;
  hasMore: boolean;
}

describe("GET /api/notifications", () => {
  test("starts empty, then fills as DMs arrive; unreadCount tracks", async () => {
    const empty = await data<FeedBody>(await req(t, "/api/notifications", { cookie: alice.cookie }));
    expect(empty.notifications).toHaveLength(0);
    expect(empty.unreadCount).toBe(0);

    await bobSendsDm("ping one");

    const filled = await data<FeedBody>(await req(t, "/api/notifications", { cookie: alice.cookie }));
    expect(filled.notifications.length).toBeGreaterThanOrEqual(1);
    expect(filled.unreadCount).toBe(filled.notifications.filter((n) => n.readAt === null).length);
  });

  test("cursor pagination + unreadOnly filter", async () => {
    for (let i = 0; i < 4; i++) await bobSendsDm(`bulk message ${i}`);

    const page1 = await data<FeedBody>(
      await req(t, "/api/notifications?limit=2", { cookie: alice.cookie }),
    );
    expect(page1.notifications).toHaveLength(2);
    expect(page1.hasMore).toBe(true);
    expect(page1.nextCursor).toBeTruthy();

    const page2 = await data<FeedBody>(
      await req(
        t,
        `/api/notifications?limit=2&cursor=${encodeURIComponent(page1.nextCursor as string)}`,
        { cookie: alice.cookie },
      ),
    );
    expect(page2.notifications).toHaveLength(2);
    const ids = new Set([...page1.notifications, ...page2.notifications].map((n) => n.id));
    expect(ids.size).toBe(4); // no overlap between pages

    const unreadOnly = await data<FeedBody>(
      await req(t, "/api/notifications?unreadOnly=1&limit=50", { cookie: alice.cookie }),
    );
    expect(unreadOnly.notifications.every((n) => n.readAt === null)).toBe(true);

    for (const query of ["limit=0", "limit=51", "limit=abc", "cursor=%%%%"]) {
      const bad = await req(t, `/api/notifications?${query}`, { cookie: alice.cookie });
      expect(bad.status).toBe(400);
    }
  });
});

describe("POST /api/notifications/read", () => {
  test("mark all, then count drops; ids subset works; invalid id → 400", async () => {
    const before = await data<FeedBody>(await req(t, "/api/notifications", { cookie: alice.cookie }));
    expect(before.unreadCount).toBeGreaterThan(0);

    const all = await req(t, "/api/notifications/read", {
      method: "POST",
      cookie: alice.cookie,
      body: {},
    });
    expect(all.status).toBe(200);
    expect((await data<{ updated: number }>(all)).updated).toBeGreaterThanOrEqual(1);

    const after = await data<FeedBody>(await req(t, "/api/notifications", { cookie: alice.cookie }));
    expect(after.unreadCount).toBe(0);

    // produce two more, mark one by id
    await bobSendsDm("subset target a");
    await bobSendsDm("subset target b");
    const feed = await data<FeedBody>(await req(t, "/api/notifications?unreadOnly=1", { cookie: alice.cookie }));
    const oneId = feed.notifications[0]?.id as string;

    const subset = await req(t, "/api/notifications/read", {
      method: "POST",
      cookie: alice.cookie,
      body: { ids: [oneId] },
    });
    expect(subset.status).toBe(200);
    expect((await data<{ updated: number }>(subset)).updated).toBe(1);

    const bad = await req(t, "/api/notifications/read", {
      method: "POST",
      cookie: alice.cookie,
      body: { ids: ["not-a-uuid"] },
    });
    expect(bad.status).toBe(400);
  });
});

describe("notification preferences (deep work)", () => {
  test("defaults without creating a row; PUT upserts; validation errors", async () => {
    const defaults = await data<{
      prefs: { deepWorkEnabled: boolean; dndStart: string; dndEnd: string; updatedAt: string | null };
    }>(await req(t, "/api/notifications/prefs", { cookie: alice.cookie }));
    expect(defaults.prefs.deepWorkEnabled).toBe(false);
    expect(defaults.prefs.dndStart).toBe("22:00");
    expect(defaults.prefs.dndEnd).toBe("07:00");

    const put = await req(t, "/api/notifications/prefs", {
      method: "PUT",
      cookie: alice.cookie,
      body: { deepWorkEnabled: true, dndStart: "08:30", dndEnd: "12:15" },
    });
    expect(put.status).toBe(200);
    const stored = await data<{ prefs: { deepWorkEnabled: boolean; dndStart: string; dndEnd: string } }>(put);
    expect(stored.prefs).toMatchObject({ deepWorkEnabled: true, dndStart: "08:30", dndEnd: "12:15" });

    // partial update keeps the other fields
    const partial = await req(t, "/api/notifications/prefs", {
      method: "PUT",
      cookie: alice.cookie,
      body: { dndEnd: "13:00" },
    });
    expect(partial.status).toBe(200);
    const merged = await data<{ prefs: { deepWorkEnabled: boolean; dndStart: string; dndEnd: string } }>(partial);
    expect(merged.prefs.deepWorkEnabled).toBe(true);
    expect(merged.prefs.dndStart).toBe("08:30");
    expect(merged.prefs.dndEnd).toBe("13:00");

    // GET reflects the persisted row (not the defaults branch)
    const afterGet = await data<{ prefs: { deepWorkEnabled: boolean; dndStart: string; dndEnd: string; updatedAt: string | null } }>(
      await req(t, "/api/notifications/prefs", { cookie: alice.cookie }),
    );
    expect(afterGet.prefs.deepWorkEnabled).toBe(true);
    expect(afterGet.prefs.dndStart).toBe("08:30");
    expect(afterGet.prefs.dndEnd).toBe("13:00");
    expect(afterGet.prefs.updatedAt).not.toBeNull();

    for (const body of [{}, { dndStart: "25:00" }, { dndEnd: "7:5" }, { deepWorkEnabled: "yes" }]) {
      const bad = await req(t, "/api/notifications/prefs", {
        method: "PUT",
        cookie: alice.cookie,
        body,
      });
      expect(bad.status).toBe(400);
    }
  });
});

describe("deep-work hold window", () => {
  test("inside the window: activity is recorded but the push is HELD", async () => {
    const now = new Date();
    const res = await req(t, "/api/notifications/prefs", {
      method: "PUT",
      cookie: alice.cookie,
      body: {
        deepWorkEnabled: true,
        dndStart: hhmm(new Date(now.getTime() - 2 * 3_600_000)),
        dndEnd: hhmm(new Date(now.getTime() + 2 * 3_600_000)),
      },
    });
    expect(res.status).toBe(200);

    t.bus.clear();
    await bobSendsDm("deep work hello");

    // feed still records everything…
    const feed = await data<FeedBody>(
      await req(t, "/api/notifications?unreadOnly=1", { cookie: alice.cookie }),
    );
    const heldNote = feed.notifications.find((n) => (n.payload as { held?: boolean }).held === true);
    expect(heldNote).toBeDefined();

    // …but no realtime push escaped during deep work
    expect(t.bus.find("unread.bumped").some((p) => p.target === `user:${alice.id}`)).toBe(false);
  });

  test("outside the window (deep work off): push flows normally", async () => {
    await req(t, "/api/notifications/prefs", {
      method: "PUT",
      cookie: alice.cookie,
      body: { deepWorkEnabled: false, dndStart: "22:00", dndEnd: "07:00" },
    });

    t.bus.clear();
    await bobSendsDm("back to normal");

    const pushes = t.bus.find("unread.bumped").filter((p) => p.target === `user:${alice.id}`);
    expect(pushes.length).toBeGreaterThanOrEqual(1);

    const feed = await data<FeedBody>(
      await req(t, "/api/notifications?unreadOnly=1", { cookie: alice.cookie }),
    );
    expect(
      feed.notifications.some((n) => (n.payload as { held?: boolean }).held === false),
    ).toBe(true);
  });
});

describe("isInDeepWorkWindow (pure logic)", () => {
  const at = (iso: string): Date => new Date(iso);

  test("disabled → never held", () => {
    expect(
      isInDeepWorkWindow({ deepWorkEnabled: false, dndStart: "22:00", dndEnd: "07:00" }, at("2026-01-01T23:00:00Z")),
    ).toBe(false);
  });

  test("same-day window: [start, end)", () => {
    const prefs = { deepWorkEnabled: true, dndStart: "09:00", dndEnd: "17:00" };
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T09:00:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T12:34:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T16:59:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T17:00:00Z"))).toBe(false); // end exclusive
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T08:59:00Z"))).toBe(false);
  });

  test("window wrapping midnight (22:00 → 07:00)", () => {
    const prefs = { deepWorkEnabled: true, dndStart: "22:00", dndEnd: "07:00" };
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T23:30:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T00:15:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T06:59:00Z"))).toBe(true);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T07:00:00Z"))).toBe(false);
    expect(isInDeepWorkWindow(prefs, at("2026-01-01T12:00:00Z"))).toBe(false);
  });

  test("zero-length window and malformed times → off", () => {
    expect(
      isInDeepWorkWindow({ deepWorkEnabled: true, dndStart: "10:00", dndEnd: "10:00" }, at("2026-01-01T10:30:00Z")),
    ).toBe(false);
    expect(
      isInDeepWorkWindow({ deepWorkEnabled: true, dndStart: "bogus", dndEnd: "10:00" }, at("2026-01-01T10:30:00Z")),
    ).toBe(false);
  });
});
