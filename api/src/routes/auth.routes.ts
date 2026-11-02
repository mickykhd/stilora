/**
 * Auth routes: mounts the Better Auth handler at /api/auth/*.
 *
 * Provides (all through Better Auth):
 *  - POST /api/auth/sign-in/magic-link   → email magic link
 *  - GET  /api/auth/magic-link/verify    → consumes the link, sets session
 *  - POST /api/auth/sign-in/social       → Google OAuth redirect
 *  - GET  /api/auth/get-session          → current session
 *  - POST /api/auth/sign-out             → revoke session
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
