/**
 * Better Auth configuration: email + password only.
 *
 * Hush deliberately has NO third-party OAuth (no Google/Apple) and no
 * magic links — accounts live in our own Postgres, period.
 *
 * Why AuthLike: Better Auth's inferred types are enormous and generic-heavy.
 * The app only ever needs `handler()` (route mounting) and
 * `api.getSession()` (requireAuth), so we expose exactly that surface with
 * plain types and cast once, here, at the boundary.
 */
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { LIMITS, type Config } from "../config";
import type { DB } from "../db/client";
import { accounts, sessions, users, verifications } from "../db/schema";

export interface AuthUser {
  id: string;
  name: string;
  email: string;
  emailVerified: boolean;
  image: string | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface AuthSession {
  id: string;
  userId: string;
  token: string;
  expiresAt: Date;
  ipAddress: string | null;
  userAgent: string | null;
  createdAt: Date;
}

export interface SessionInfo {
  user: AuthUser;
  session: AuthSession;
}

export interface AuthLike {
  handler(request: Request): Promise<Response>;
  api: {
    getSession(options: { headers: Headers }): Promise<SessionInfo | null>;
  };
}

export interface CreateAuthOptions {
  db: DB;
  config: Config;
}

export function createAuth(options: CreateAuthOptions): AuthLike {
  const { db, config } = options;

  const auth = betterAuth({
    secret: config.betterAuthSecret,
    baseURL: config.betterAuthUrl,
    // Better Auth manages these four tables through the drizzle adapter. The
    // schema map keys are Better Auth *model* names; the drizzle objects carry
    // the real (plural) Postgres table names.
    database: drizzleAdapter(db, {
      provider: "pg",
      schema: { user: users, session: sessions, account: accounts, verification: verifications },
    }),
    session: {
      expiresIn: LIMITS.sessionTtl,
      updateAge: 24 * 60 * 60,
      cookieCache: { enabled: false }, // always read the session table: simplest, testable
    },
    // Our own token-bucket limiter (src/ratelimit) is the single rate limit
    // for this API — better-auth's built-in limiter would need Redis to be
    // correct multi-instance, so it stays off.
    rateLimit: { enabled: false },
    // The only sign-in method: email + password stored in our database.
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 8,
      disableSignUp: false, // account creation goes through the same endpoint
    },
    // No socialProviders — third-party OAuth is intentionally absent.
    plugins: [],
  });

  // Trusted cast: AuthLike is a structural subset of Better Auth's instance.
  return auth as unknown as AuthLike;
}
