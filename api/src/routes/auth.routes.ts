/**
 * Auth routes: mounts the Better Auth handler at /api/auth/*.
 *
 * Provides (all through Better Auth):
 *  - POST /api/auth/sign-up/email        → create account (email + password)
 *  - POST /api/auth/sign-in/email        → sign in (email + password)
 *  - GET  /api/auth/get-session          → current session
 *  - POST /api/auth/sign-out             → revoke session
 *
 * There is intentionally NO third-party OAuth and NO magic link — every
 * account lives in our own database.
 */
import { Hono } from "hono";
import type { AppContext, AppEnv } from "../context";

export function authRoutes(ctx: AppContext): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.on(["GET", "POST", "PUT", "PATCH", "DELETE"], "/api/auth/*", (c) => {
    return ctx.auth.handler(c.req.raw);
  });

  return app;
}
