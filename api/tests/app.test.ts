/**
 * App-level pipeline: health (ok + degraded), 404/500 envelopes, request ids,
 * CORS basics (deep CORS coverage lives in security.test.ts).
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
let dying: TestApp;
let dyingUser: SignedInUser;

beforeAll(async () => {
  t = await createTestApp();

  // a second app we intentionally break to reach the 500/degraded paths
  dying = await createTestApp();
  dyingUser = await signIn(dying, uniqueEmail("dying"));
  await makeWorkspace(dying, dyingUser.cookie, "Prepared WS");
});
afterAll(async () => {
  await t?.close();
  await dying?.close();
});

describe("GET /api/health", () => {
  test("no auth required; reports service + database + uptime", async () => {
    const res = await req(t, "/api/health");
    expect(res.status).toBe(200);
    const d = await data<{
      status: string;
      service: string;
      database: string;
      uptimeSeconds: number;
      time: string;
    }>(res);
    expect(d.status).toBe("ok");
    expect(d.service).toBe("stilora-api");
    expect(d.database).toBe("up");
    expect(d.uptimeSeconds).toBeGreaterThanOrEqual(0);
    expect(Number.isNaN(Date.parse(d.time))).toBe(false);
  });

  test("response shape is {data} — never an error envelope", async () => {
    const body = (await (await req(t, "/api/health")).json()) as Record<string, unknown>;
    expect(Object.keys(body)).toEqual(["data"]);
    expect(body.error).toBeUndefined();
  });
});

describe("error envelopes", () => {
  test("404 unknown route keeps {error,status} === http status", async () => {
    const res = await req(t, "/api/nope/nope/nope");
    expect(res.status).toBe(404);
    const f = await failure(res); // helper asserts body.status === res.status
    expect(f.error).toBe("not found");
  });

  test("401 keeps {error,status} contract", async () => {
    const res = await req(t, "/api/workspaces");
    expect(res.status).toBe(401);
    const f = await failure(res);
    expect(f.error).toBe("unauthorized");
    expect(f.status).toBe(401);
  });
});

describe("unexpected failures (onError path)", () => {
  test("database gone → health reports degraded 503, routes answer 500 {error,status}", async () => {
    // sanity while alive
    const alive = await req(dying, "/api/health");
    expect(alive.status).toBe(200);

    // break the world (through the helper so afterAll stays a no-op)
    await dying.close();

    const degraded = await req(dying, "/api/health");
    expect(degraded.status).toBe(503);
    const healthBody = await data<{ status: string; database: string }>(degraded);
    expect(healthBody.status).toBe("degraded");
    expect(healthBody.database).toBe("down");

    // session lookup now throws inside requireAuth → onError → 500 envelope
    const broken = await req(dying, "/api/workspaces", { cookie: dyingUser.cookie });
    expect(broken.status).toBe(500);
    const f = await failure(broken);
    expect(f.error).toBe("internal server error");
    expect(f.status).toBe(500);
    expect(broken.headers.get("x-request-id")).toBeTruthy(); // id still echoed
  });
});
