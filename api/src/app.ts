/**
 * Application assembly: middleware pipeline + route wiring.
 *
 * `createApp(deps?)` accepts overrides for EVERY external dependency so tests
 * run fully in-memory (PGlite database, MemoryBus, fake LiveKit, local
 * storage, injected config). With no arguments it resolves production
 * defaults from the environment (see src/index.ts).
 */
import { Hono } from "hono";
import { createAuth, type AuthLike } from "./auth/auth";
import type { AppContext, AppEnv } from "./context";
import { loadConfig, type Config } from "./config";
import { createDb, type DB } from "./db/client";
import { AblyBus, MemoryBus, type EventBus } from "./events/bus";
import { TokenBucketLimiter } from "./ratelimit/limiter";
import { createLiveKitTokenMinter, createLiveKitVoiceStateProvider, type TokenMinter, type VoiceStateProvider } from "./livekit/token";
import { createUploadSigner, type UploadSigner } from "./storage/uploads";
import { fail } from "./http";
import { authRoutes } from "./routes/auth.routes";
import { channelRoutes } from "./routes/channel.routes";
import { dmRoutes } from "./routes/dm.routes";
import { healthRoutes } from "./routes/health.routes";
import { notificationRoutes } from "./routes/notification.routes";
import { pinRoutes } from "./routes/pin.routes";
import { reactionRoutes } from "./routes/reaction.routes";
import { searchRoutes } from "./routes/search.routes";
import { threadRoutes } from "./routes/thread.routes";
import { uploadRoutes } from "./routes/upload.routes";
import { voiceRoutes } from "./routes/voice.routes";
import { workspaceRoutes } from "./routes/workspace.routes";
import { randomUUID } from "node:crypto";

export interface CreateAppDeps {
  config?: Config;
  db?: DB;
  auth?: AuthLike;
  bus?: EventBus;
  tokens?: TokenMinter | null;
  voice?: VoiceStateProvider | null;
  uploads?: UploadSigner;
  limiter?: TokenBucketLimiter;
}

/** First (original client) entry of x-forwarded-for, or a stable fallback. */
export function clientIp(
  header: string | undefined,
  trustProxy: boolean,
): string {
  if (!trustProxy) return "local";
  const first = header?.split(",")[0]?.trim();
  return first && first.length > 0 ? first : "local";
}

export function createApp(deps: CreateAppDeps = {}): Hono<AppEnv> {
  const config = deps.config ?? loadConfig();

  // Resolve every dependency once; tests override any of them.
  const dbHandle = deps.db ? null : createDb(config.databaseUrl);
  const db = deps.db ?? (dbHandle as { db: DB }).db;
  const auth =
    deps.auth ??
    createAuth({
      db,
      config,
    });
  const bus: EventBus =
    deps.bus ?? (config.ablyApiKey ? new AblyBus(config.ablyApiKey) : new MemoryBus());
  const tokens: TokenMinter | null =
    deps.tokens !== undefined
      ? deps.tokens
      : config.livekit
        ? createLiveKitTokenMinter(config.livekit)
        : null;
  const voice: VoiceStateProvider | null =
    deps.voice !== undefined
      ? deps.voice
      : config.livekit
        ? createLiveKitVoiceStateProvider(config.livekit)
        : null;
  const uploads: UploadSigner = deps.uploads ?? createUploadSigner(config.storage);
  const limiter: TokenBucketLimiter =
    deps.limiter ??
    new TokenBucketLimiter({
      authPerMin: config.rateLimit.authPerMin,
      routePerMin: config.rateLimit.routePerMin,
      globalPerMin: config.rateLimit.globalPerMin,
    });

  const ctx: AppContext = { config, db, auth, bus, tokens, voice, uploads, limiter };

  const app = new Hono<AppEnv>();

  // 1. request id — echoed on every response, used in every error log
  app.use("*", async (c, next) => {
    c.set("requestId", randomUUID());
    c.header("x-request-id", c.get("requestId"));
    await next();
  });

  // 2. shared context for the middleware security boundary
  app.use("*", async (c, next) => {
    c.set("ctx", ctx);
    await next();
  });

  // 3. CORS — explicit allow-list, unknown origins are denied (403) and never
  //    receive Access-Control-* headers. Requests without an Origin header
  //    (server-to-server, curl, tests) pass through untouched.
  app.use("*", async (c, next) => {
    const origin = c.req.header("origin");
    const allowed = origin !== undefined && config.corsOrigins.includes(origin);
    const headers: Record<string, string> = origin
      ? {
          "Access-Control-Allow-Origin": origin,
          "Access-Control-Allow-Credentials": "true",
          "Access-Control-Allow-Headers": "content-type, authorization, x-request-id",
          "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
          "Access-Control-Expose-Headers": "x-request-id",
          "Access-Control-Max-Age": "600",
          Vary: "Origin",
        }
      : {};

    if (c.req.method === "OPTIONS") {
      if (origin !== undefined && !allowed) return fail(c, 403, "origin not allowed");
      return c.body(null, 204, headers);
    }
    if (origin !== undefined && !allowed) return fail(c, 403, "origin not allowed");

    await next();
    if (origin !== undefined && allowed) {
      for (const [key, value] of Object.entries(headers)) c.res.headers.set(key, value);
    }
  });

  // 4. body size guard → 413 before we ever parse the payload
  app.use("*", async (c, next) => {
    const rawLength = c.req.header("content-length");
    if (rawLength !== undefined) {
      const length = Number(rawLength);
      if (!Number.isFinite(length) || length > config.maxBodyBytes) {
        return fail(c, 413, `payload too large (limit ${config.maxBodyBytes} bytes)`);
      }
    }
    await next();
  });

  // 5. rate limiting (in-process token buckets; health checks exempt)
  app.use("*", async (c, next) => {
    if (c.req.path === "/api/health") return next();
    const ip = clientIp(c.req.header("x-forwarded-for"), config.rateLimit.trustProxy);

    const global = limiter.check(`global:${ip}`, "global");
    if (!global.allowed) {
      return c.json({ error: "rate limit exceeded", status: 429 }, 429, {
        "Retry-After": String(global.retryAfterSeconds),
      });
    }

    const isAuthRoute = c.req.path.startsWith("/api/auth");
    const decision = isAuthRoute
      ? limiter.check(`auth:${ip}`, "auth")
      : limiter.check(`route:${ip}:${c.req.path}`, "route");
    if (!decision.allowed) {
      return c.json({ error: "rate limit exceeded", status: 429 }, 429, {
        "Retry-After": String(decision.retryAfterSeconds),
      });
    }
    await next();
  });

  // --- routes ---------------------------------------------------------------
  app.route("/", healthRoutes(ctx));
  app.route("/", authRoutes(ctx));
  app.route("/", workspaceRoutes(ctx));
  app.route("/", channelRoutes(ctx));
  app.route("/", threadRoutes(ctx));
  app.route("/", reactionRoutes(ctx));
  app.route("/", pinRoutes(ctx));
  app.route("/", dmRoutes(ctx));
  app.route("/", searchRoutes(ctx));
  app.route("/", voiceRoutes(ctx));
  app.route("/", uploadRoutes(ctx));
  app.route("/", notificationRoutes(ctx));

  // --- error handling: consistent shape, request id in the log ---------------
  app.onError((err, c) => {
    const requestId = c.get("requestId") ?? "-";
    console.error(
      `[stilora-api] ${requestId} ${c.req.method} ${c.req.path} -> 500`,
      err instanceof Error ? (err.stack ?? err.message) : err,
    );
    return fail(c, 500, "internal server error");
  });

  app.notFound((c) => fail(c, 404, "not found"));

  return app;
}
