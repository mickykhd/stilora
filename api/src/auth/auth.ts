/**
 * Better Auth configuration: magic link + Google OAuth.
 *
 * Why AuthLike: Better Auth's inferred types are enormous and generic-heavy.
 * The app only ever needs `handler()` (route mounting) and
 * `api.getSession()` (requireAuth), so we expose exactly that surface with
 * plain types and cast once, here, at the boundary.
 *
 * Email delivery: the default sender logs the link AND records it in an
 * in-memory inbox (capped) so tests can complete the flow offline. Swap in a
 * real sender (SMTP/Resend/Postmark) by passing `sendMagicLink` — see README.
 */
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { magicLink } from "better-auth/plugins";
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

export interface MagicLinkMessage {
  email: string;
  url: string;
  token: string;
  at: Date;
}

const inbox: MagicLinkMessage[] = [];
const INBOX_CAP = 50;

/** Pop the most recent captured magic link for an email (tests / dev console). */
export function takeMagicLink(email: string): MagicLinkMessage | null {
  for (let i = inbox.length - 1; i >= 0; i--) {
    const msg = inbox[i];
    if (msg && msg.email === email) {
      inbox.splice(i, 1);
      return msg;
    }
  }
  return null;
}

export function clearMagicLinkInbox(): void {
  inbox.length = 0;
}

/** Number of captured-but-unclaimed magic links (test/diagnostic seam). */
export function magicLinkInboxSize(): number {
  return inbox.length;
}

export type MagicLinkSender = (message: MagicLinkMessage) => void | Promise<void>;

const defaultSender: MagicLinkSender = (message) => {
  if (inbox.length >= INBOX_CAP) inbox.shift();
  inbox.push(message);
  // Zero-dependency default: log the link so self-hosters can click it in
  // dev. Production deployments should inject a real email sender.
  console.log(`[auth] magic link for ${message.email}: ${message.url}`);
};

export interface CreateAuthOptions {
  db: DB;
  config: Config;
  sendMagicLink?: MagicLinkSender;
}

export function createAuth(options: CreateAuthOptions): AuthLike {
  const { db, config } = options;
  const sender = options.sendMagicLink ?? defaultSender;

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
    socialProviders: config.google
      ? {
          google: {
            clientId: config.google.clientId,
            clientSecret: config.google.clientSecret,
          },
        }
      : {},
    plugins: [
      magicLink({
        expiresIn: LIMITS.magicLinkTtl,
        sendMagicLink: (message) =>
          sender({ email: message.email, url: message.url, token: message.token, at: new Date() }),
      }),
    ],
  });

  // Trusted cast: AuthLike is a structural subset of Better Auth's instance.
  return auth as unknown as AuthLike;
}
