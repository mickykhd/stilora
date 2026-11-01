/**
 * Test harness — zero external services.
 *
 *  - Database: PGlite (Postgres compiled to WASM) via drizzle's pglite driver.
 *    The REAL migration SQL runs against it on every createTestApp(), so the
 *    suite also proves the migrations work on a clean Postgres.
 *  - Auth: the real Better Auth email+password flow over HTTP — accounts are
 *    created in-process against PGlite; no email, no network, no OAuth.
 *  - Realtime: MemoryBus.  Voice: injected fakes.  Storage: local no-op.
 *
 * Env is set at module load, BEFORE any src module that reads it is imported;
 * src modules are imported dynamically inside createTestApp().
 */
import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import type { Hono } from "hono";
import type { AppEnv } from "../src/context";
import type { Config } from "../src/config";
import type { DB } from "../src/db/client";
import type { MemoryBus } from "../src/events/bus";
import * as schema from "../src/db/schema";

export const TEST_ENV: Record<string, string> = {
  NODE_ENV: "test",
  // Never dialled — createTestApp() injects a PGlite-backed drizzle instance.
  DATABASE_URL: "postgres://hush@localhost:5432/hush",
  BETTER_AUTH_SECRET: "test-secret-must-be-at-least-32-chars!!",
  BETTER_AUTH_URL: "http://localhost:3000",
  ALLOWED_ORIGINS: "http://localhost:5173",
  TRUST_PROXY: "true",
  // Generous defaults; ratelimit.test.ts overrides them per app instance.
  RATE_LIMIT_AUTH_PER_MIN: "10000",
  RATE_LIMIT_ROUTE_PER_MIN: "50000",
  RATE_LIMIT_GLOBAL_PER_MIN: "100000",
};

for (const [key, value] of Object.entries(TEST_ENV)) {
  if (process.env[key] === undefined) process.env[key] = value;
}

export interface TestApp {
  app: Hono<AppEnv>;
  db: DB;
  bus: MemoryBus;
  config: Config;
  pglite: PGlite;
  close: () => Promise<void>;
}

export interface CreateTestAppOptions {
  /** false → no LiveKit fakes injected (routes answer 503). Default true.
   *  "env" → inject nothing so createApp builds the REAL LiveKit clients from
   *  env config (construction only — signing is offline, no network). */
  voice?: boolean | "env";
}

export async function createTestApp(
  envOverrides: Record<string, string> = {},
  options: CreateTestAppOptions = {},
): Promise<TestApp> {
  const pglite = new PGlite();
  // Both drivers implement the identical pg-core query builder; only the
  // transport differs (WASM vs wire protocol). Safe test-only cast.
  const db = drizzle(pglite, { schema }) as unknown as DB;

  const { loadConfig } = await import("../src/config");
  const config = loadConfig({ ...process.env, ...TEST_ENV, ...envOverrides });

  const { applyMigrations } = await import("../src/db/migrate");
  await applyMigrations(db);

  const { MemoryBus } = await import("../src/events/bus");
  const bus = new MemoryBus();

  let closed = false;

  const { createApp } = await import("../src/app");
  const voiceMode = options.voice ?? true;
  const app = createApp({
    config,
    db,
    bus,
    ...(voiceMode === "env"
      ? {} // omit tokens/voice → createApp builds them from config
      : {
          tokens: voiceMode
            ? ({
                mint: async (o) =>
                  `test-token|${o.room}|${o.identity}|${o.name}|${o.ttlSeconds ?? 0}`,
              } as const)
            : null,
          voice: voiceMode
            ? ({
                getState: async (room: string) => ({
                  room,
                  participants: [
                    {
                      identity: "participant-1",
                      name: "Ada",
                      state: "ACTIVE",
                      joinedAt: "2026-01-01T00:00:00.000Z",
                    },
                  ],
                  startedAt: "2026-01-01T00:00:00.000Z",
                }),
              } as const)
            : null,
        }),
  });

  return {
    app,
    db,
    bus,
    config,
    pglite,
    close: async () => {
      if (closed) return; // idempotent — tests may close an app early on purpose
      closed = true;
      try {
        await pglite.close();
      } catch {
        // a test may have closed the handle directly; closing twice is fine here
      }
    },
  };
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

let ipCounter = 0;

/** Unique client IP per request → per-IP buckets never leak between tests. */
export function newIp(): string {
  ipCounter += 1;
  return `10.0.${(ipCounter >> 8) & 255}.${ipCounter & 255}`;
}

export interface RequestOptions {
  method?: string;
  body?: unknown;
  /** Used verbatim (bypasses JSON.stringify) for oversized/malformed bodies. */
  rawBody?: string;
  cookie?: string | null;
  ip?: string;
  headers?: Record<string, string>;
}

export async function req(t: TestApp, path: string, options: RequestOptions = {}): Promise<Response> {
  const hasBody = options.body !== undefined || options.rawBody !== undefined;
  const headers: Record<string, string> = {
    "x-forwarded-for": options.ip ?? newIp(),
    ...(options.cookie ? { cookie: options.cookie } : {}),
    ...(hasBody ? { "content-type": "application/json" } : {}),
    ...options.headers,
  };
  const method = options.method ?? (hasBody ? "POST" : "GET");
  const body =
    options.rawBody !== undefined
      ? options.rawBody
      : options.body !== undefined
        ? JSON.stringify(options.body)
        : undefined;
  return await t.app.request(path, { method, headers, body });
}

export interface ApiSuccess<T> {
  data: T;
}
export interface ApiFailure {
  error: string;
  status: number;
}

/** Extract `data` from a success body, failing loudly otherwise. */
export async function data<T>(res: Response): Promise<T> {
  const body = (await res.json()) as { data?: T; error?: string };
  if (body.data === undefined) {
    throw new Error(`expected success body, got ${JSON.stringify(body)} (status ${res.status})`);
  }
  return body.data;
}

/** Extract `{error, status}` from a failure body, validating the shape. */
export async function failure(res: Response): Promise<ApiFailure> {
  const body = (await res.json()) as ApiFailure;
  if (typeof body.error !== "string" || typeof body.status !== "number") {
    throw new Error(`expected {error,status} body, got ${JSON.stringify(body)}`);
  }
  if (body.status !== res.status) {
    throw new Error(`body status ${body.status} !== http status ${res.status}`);
  }
  return body;
}

// ---------------------------------------------------------------------------
// Auth + fixtures
// ---------------------------------------------------------------------------

export interface SignedInUser {
  id: string;
  email: string;
  cookie: string;
}

let userSeq = 0;
export function uniqueEmail(prefix = "user"): string {
  userSeq += 1;
  return `${prefix}-${userSeq}-${Math.random().toString(36).slice(2, 8)}@example.com`;
}

function extractSessionCookie(res: Response): string | null {
  for (const setCookie of res.headers.getSetCookie()) {
    if (setCookie.includes("session_token")) {
      return setCookie.split(";")[0] ?? null;
    }
  }
  return null;
}

/**
 * Create an account and return its session — the real email+password flow
 * over HTTP (no network beyond the local app). If the account already
 * exists (same fixture reused across tests), fall back to sign-in with the
 * same credentials.
 */
const TEST_PASSWORD = "test-password-123";

export async function signIn(
  t: TestApp,
  email: string,
  name?: string,
): Promise<SignedInUser> {
  const signUpRes = await req(t, "/api/auth/sign-up/email", {
    method: "POST",
    body: { email, password: TEST_PASSWORD, name: name ?? email.split("@")[0] },
  });

  let cookie = extractSessionCookie(signUpRes);
  if (!cookie) {
    // Account already exists → sign in with email + password instead.
    const signInRes = await req(t, "/api/auth/sign-in/email", {
      method: "POST",
      body: { email, password: TEST_PASSWORD },
    });
    cookie = extractSessionCookie(signInRes);
  }
  if (!cookie) {
    throw new Error(
      `no session cookie after email/password auth (sign-up ${signUpRes.status}): ${await signUpRes.text()}`,
    );
  }

  const sessionRes = await req(t, "/api/auth/get-session", { cookie });
  const sessionBody = (await sessionRes.json()) as { user?: { id: string; email: string } } | null;
  if (!sessionBody?.user) {
    throw new Error(`get-session returned no user for ${email}`);
  }
  return { id: sessionBody.user.id, email: sessionBody.user.email, cookie };
}

export interface WorkspaceFixture {
  id: string;
  slug: string;
  inviteCode: string;
}

export async function makeWorkspace(
  t: TestApp,
  cookie: string,
  name = "Test Workspace",
): Promise<WorkspaceFixture> {
  const res = await req(t, "/api/workspaces", { method: "POST", cookie, body: { name } });
  if (res.status !== 201) throw new Error(`workspace create failed: ${await res.text()}`);
  return await data<{ workspace: WorkspaceFixture }>(res).then((d) => d.workspace);
}

/** Test-only shortcut: insert a membership row directly (setup, not behavior). */
export async function addMember(
  t: TestApp,
  workspaceId: string,
  userId: string,
  role: "owner" | "admin" | "member" = "member",
): Promise<void> {
  await t.db
    .insert(schema.workspaceMembers)
    .values({ workspaceId, userId, role })
    .onConflictDoNothing();
}

export async function makeChannel(
  t: TestApp,
  cookie: string,
  workspaceId: string,
  name: string,
  kind: "public" | "private" = "public",
): Promise<{ id: string; name: string }> {
  const res = await req(t, `/api/workspaces/${workspaceId}/channels`, {
    method: "POST",
    cookie,
    body: { name, kind },
  });
  if (res.status !== 201) throw new Error(`channel create failed: ${await res.text()}`);
  return (await data<{ channel: { id: string; name: string } }>(res)).channel;
}

export async function postMessage(
  t: TestApp,
  cookie: string,
  channelId: string,
  content: string,
): Promise<{ id: string; content: string }> {
  const res = await req(t, `/api/channels/${channelId}/messages`, {
    method: "POST",
    cookie,
    body: { content },
  });
  if (res.status !== 201) throw new Error(`message post failed: ${await res.text()}`);
  return (await data<{ message: { id: string; content: string } }>(res)).message;
}
