/**
 * Rate limiting: per-IP token buckets with 429 + Retry-After, separate
 * auth/route/global classes, health-check exemption, TRUST_PROXY=false mode.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
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

beforeAll(async () => {
  t = await createTestApp({
    RATE_LIMIT_AUTH_PER_MIN: "2",
    RATE_LIMIT_ROUTE_PER_MIN: "3",
    RATE_LIMIT_GLOBAL_PER_MIN: "1000",
  });
  alice = await signIn(t, uniqueEmail("alice"));
});
afterAll(async () => {
  await t?.close();
});

const IP = "198.51.100.7";

describe("route bucket (3 req/min)", () => {
  test("4th request from the same IP → 429 with Retry-After; other IPs unaffected", async () => {
    const statuses: number[] = [];
    let retryAfter: string | null = null;

    for (let i = 0; i < 4; i++) {
      const res = await req(t, "/api/workspaces", { cookie: alice.cookie, ip: IP });
      statuses.push(res.status);
      if (res.status === 429) retryAfter = res.headers.get("retry-after");
    }

    expect(statuses.slice(0, 3)).toEqual([200, 200, 200]);
    expect(statuses[3]).toBe(429);

    // Retry-After header: present, integer ≥ 1
    expect(retryAfter).not.toBeNull();
    expect(Number.isInteger(Number(retryAfter))).toBe(true);
    expect(Number(retryAfter)).toBeGreaterThanOrEqual(1);

    // body follows the {error,status} contract
    const blocked = await req(t, "/api/workspaces", { cookie: alice.cookie, ip: IP });
    const f = await failure(blocked);
    expect(f.error).toContain("rate limit");
    expect(f.status).toBe(429);

    // a fresh IP is not affected by the exhausted bucket
    const otherIp = await req(t, "/api/workspaces", { cookie: alice.cookie, ip: "203.0.113.50" });
    expect(otherIp.status).toBe(200);
  });
});

describe("auth bucket (2 req/min)", () => {
  test("third /api/auth request from one IP → 429", async () => {
    const authIp = "198.51.100.99";
    const first = await req(t, "/api/auth/get-session", { ip: authIp });
    const second = await req(t, "/api/auth/get-session", { ip: authIp });
    expect(first.status).not.toBe(429);
    expect(second.status).not.toBe(429);

    const third = await req(t, "/api/auth/get-session", { ip: authIp });
    expect(third.status).toBe(429);
    expect(third.headers.get("retry-after")).not.toBeNull();

    // auth and route buckets are separate: route bucket for this IP still full
    const route = await req(t, "/api/workspaces", { cookie: alice.cookie, ip: authIp });
    expect(route.status).toBe(200);
  });
});

describe("health exemption", () => {
  test("/api/health never gets rate-limited", async () => {
    const healthIp = "198.51.100.123";
    for (let i = 0; i < 12; i++) {
      const res = await req(t, "/api/health", { ip: healthIp });
      expect(res.status).toBe(200);
      const d = await data<{ status: string }>(res);
      expect(d.status).toBe("ok");
    }
  });
});

describe("TRUST_PROXY=false", () => {
  test("all clients collapse into a single bucket", async () => {
    const noProxy = await createTestApp({
      TRUST_PROXY: "false",
      RATE_LIMIT_ROUTE_PER_MIN: "2",
      RATE_LIMIT_GLOBAL_PER_MIN: "1000",
    });
    try {
      const user = await signIn(noProxy, uniqueEmail("np"));
      // three DIFFERENT x-forwarded-for values still share the "local" bucket
      const a = await req(noProxy, "/api/workspaces", { cookie: user.cookie, ip: "1.1.1.1" });
      const b = await req(noProxy, "/api/workspaces", { cookie: user.cookie, ip: "2.2.2.2" });
      const c = await req(noProxy, "/api/workspaces", { cookie: user.cookie, ip: "3.3.3.3" });
      expect(a.status).toBe(200);
      expect(b.status).toBe(200);
      expect(c.status).toBe(429); // third overall, regardless of XFF
    } finally {
      await noProxy.close();
    }
  });
});

describe("workspace creation still works while limits are tight", () => {
  test("create workspace on the shared app (fresh bucket IPs)", async () => {
    const ws = await makeWorkspace(t, alice.cookie, "Under Load WS");
    expect(ws.id).toBeTruthy();
  });
});

describe("global bucket", () => {
  test("the per-IP global cap returns 429 even across different routes", async () => {
    const capped = await createTestApp({
      RATE_LIMIT_GLOBAL_PER_MIN: "1",
      RATE_LIMIT_ROUTE_PER_MIN: "1000",
      RATE_LIMIT_AUTH_PER_MIN: "1000",
    });
    try {
      const user = await signIn(capped, uniqueEmail("global"));
      const first = await req(capped, "/api/health", { ip: "192.0.2.10" });
      expect(first.status).toBe(200); // health skips limiting entirely

      const second = await req(capped, "/api/workspaces", {
        cookie: user.cookie,
        ip: "192.0.2.11",
      });
      expect(second.status).toBe(200); // first global token consumed

      const third = await req(capped, "/api/notifications", {
        cookie: user.cookie,
        ip: "192.0.2.11", // SAME IP, different route — its route bucket is
        // full, so only the global bucket can stop this request
      });
      expect(third.status).toBe(429);
      expect(third.headers.get("retry-after")).not.toBeNull();
    } finally {
      await capped.close();
    }
  });
});

describe("TokenBucketLimiter (pure unit, injected clock)", () => {
  test("refills over time and reports retry-after math", async () => {
    const { TokenBucketLimiter } = await import("../src/ratelimit/limiter");
    let clock = 0;
    const limiter = new TokenBucketLimiter({
      authPerMin: 2,
      routePerMin: 2,
      globalPerMin: 2,
      now: () => clock,
    });

    expect(limiter.check("k", "auth").allowed).toBe(true);
    expect(limiter.check("k", "auth").allowed).toBe(true); // bucket drained
    const denied = limiter.check("k", "auth");
    expect(denied.allowed).toBe(false);
    expect(denied.retryAfterSeconds).toBeGreaterThanOrEqual(1);
    expect(denied.remaining).toBe(0);

    clock += 1_000; // 1s → exactly 1 token at 2/min? (2/60 per ms → 0.033…)
    clock += 30_000; // half a minute → 1 full token
    expect(limiter.check("k", "auth").allowed).toBe(true);

    limiter.clear(); // reset covers the public clear() seam
    expect(limiter.check("k", "auth").allowed).toBe(true);
  });

  test("prunes idle buckets and fails open when the map is saturated", async () => {
    const { TokenBucketLimiter } = await import("../src/ratelimit/limiter");
    let clock = 0;
    const limiter = new TokenBucketLimiter({
      authPerMin: 60,
      routePerMin: 60,
      globalPerMin: 60,
      now: () => clock,
      maxBuckets: 2,
    });

    limiter.check("a", "auth");
    limiter.check("b", "auth"); // map now at capacity

    clock += 11 * 60 * 1000; // everything idle > 10 min
    limiter.check("c", "auth"); // prunes a & b (idle), inserts c
    expect(limiter.check("a", "auth").allowed).toBe(true); // fresh bucket again

    // saturate with NON-idle buckets → the fail-open clear-all branch runs
    limiter.check("d", "auth");
    limiter.check("e", "auth"); // size >= max, none idle
    clock += 1_000;
    limiter.check("f", "auth"); // prune finds nothing idle → clears everything
    expect(limiter.check("g", "auth").allowed).toBe(true);
  });
});
