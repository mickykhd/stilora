/**
 * THE security boundary.
 *
 * Every non-health route composes these middlewares. The 4-way matrix that
 * tests/auth.matrix.test.ts enforces on EVERY endpoint:
 *
 *   1. valid session + member           → 2xx with correct data
 *   2. no session                       → 401 {error:"unauthorized"}
 *   3. session but not a member         → 403 {error:"forbidden"}   ← uniform:
 *      "workspace does not exist" and "workspace exists but you are not a
 *      member" are INDISTINGUISHABLE here, so ids of foreign workspaces,
 *      channels and messages can never be enumerated.
 *   4. malformed id / bad token / body  → 4xx; hammering → 429 (limiter)
 *
 * Identity ALWAYS comes from the session: no handler ever reads author ids or
 * "edited by" from the request body.
 */
import { and, eq } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../context";
import {
  channelMembers,
  channels,
  messages,
  workspaceMembers,
  workspaces,
  type WorkspaceRole,
} from "../db/schema";
import { fail, isUuid } from "../http";

export type { AppEnv };

const ROLE_RANK: Record<WorkspaceRole, number> = { member: 1, admin: 2, owner: 3 };

export function roleAtLeast(actual: WorkspaceRole, required: WorkspaceRole): boolean {
  return ROLE_RANK[actual] >= ROLE_RANK[required];
}

/**
 * Resolve a resource id from, in order: path param → query string → JSON body.
 * Lets POST /api/voice/token {channelId} and GET /api/voice/state?channelId=
 * reuse the exact same channel check as path-param routes.
 */
async function resolveId(
  c: Parameters<MiddlewareHandler<AppEnv>>[0],
  key: string,
): Promise<string | undefined> {
  const fromPath = c.req.param(key);
  if (fromPath !== undefined) return fromPath;
  const fromQuery = c.req.query(key);
  if (fromQuery !== undefined) return fromQuery;
  if ((c.req.header("content-type") ?? "").includes("application/json")) {
    try {
      const body: unknown = await c.req.json();
      if (typeof body === "object" && body !== null) {
        const value = (body as Record<string, unknown>)[key];
        if (typeof value === "string") return value;
      }
    } catch {
      return undefined; // malformed body → the route's own validation reports it
    }
  }
  return undefined;
}

/** 401 unless a valid session was established by requireAuth. */
export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const ctx = c.get("ctx");
  const session = await ctx.auth.api.getSession({ headers: c.req.raw.headers });
  if (!session) return fail(c, 401, "unauthorized");
  c.set("session", session);
  c.set("userId", session.user.id);
  await next();
};

/**
 * Require workspace membership (optionally with a minimum role).
 * Missing workspace AND missing membership both answer 403 — see header.
 */
export function requireWorkspaceMember(
  param = "workspaceId",
  minRole: WorkspaceRole = "member",
): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const session = c.get("session");
    if (!session) return fail(c, 401, "unauthorized");
    const raw = c.req.param(param);
    if (!raw || !isUuid(raw)) return fail(c, 400, "invalid workspace id");

    const rows = await c
      .get("ctx")
      .db.select({ membership: workspaceMembers, workspace: workspaces })
      .from(workspaceMembers)
      .innerJoin(workspaces, eq(workspaces.id, workspaceMembers.workspaceId))
      .where(
        and(eq(workspaceMembers.workspaceId, raw), eq(workspaceMembers.userId, session.user.id)),
      )
      .limit(1);

    const row = rows[0];
    // not-a-member and not-found are deliberately the SAME response (403).
    if (!row) return fail(c, 403, "forbidden");
    if (!roleAtLeast(row.membership.role, minRole)) return fail(c, 403, "forbidden");

    c.set("workspaceId", raw);
    c.set("membership", row.membership);
    await next();
  };
}

/**
 * Require access to a channel:
 *  - workspace member AND (public channel OR member of the private/dm channel).
 * Sets ctx vars: channel, workspaceId, membership.
 */
export function requireChannelMember(param = "channelId"): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const session = c.get("session");
    if (!session) return fail(c, 401, "unauthorized");
    const raw = await resolveId(c, param);
    if (!raw || !isUuid(raw)) return fail(c, 400, "invalid channel id");

    const db = c.get("ctx").db;
    const channelRows = await db
      .select()
      .from(channels)
      .where(eq(channels.id, raw))
      .limit(1);
    const channel = channelRows[0];
    // unknown channel ≡ foreign channel → 403 (no existence oracle)
    if (!channel) return fail(c, 403, "forbidden");

    const membershipRows = await db
      .select()
      .from(workspaceMembers)
      .where(
        and(
          eq(workspaceMembers.workspaceId, channel.workspaceId),
          eq(workspaceMembers.userId, session.user.id),
        ),
      )
      .limit(1);
    const membership = membershipRows[0];
    if (!membership) return fail(c, 403, "forbidden");

    if (channel.kind !== "public") {
      const memberRows = await db
        .select({ id: channelMembers.id })
        .from(channelMembers)
        .where(
          and(eq(channelMembers.channelId, channel.id), eq(channelMembers.userId, session.user.id)),
        )
        .limit(1);
      if (!memberRows[0]) return fail(c, 403, "forbidden");
    }

    c.set("channel", channel);
    c.set("workspaceId", channel.workspaceId);
    c.set("membership", membership);
    await next();
  };
}

/**
 * Require access to a message's channel (loads message + channel + workspace
 * membership). Unknown message ≡ foreign message → 403.
 */
export function requireMessageAccess(param = "messageId"): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const session = c.get("session");
    if (!session) return fail(c, 401, "unauthorized");
    const raw = c.req.param(param);
    if (!raw || !isUuid(raw)) return fail(c, 400, "invalid message id");

    const db = c.get("ctx").db;
    const rows = await db
      .select({ message: messages, channel: channels })
      .from(messages)
      .innerJoin(channels, eq(channels.id, messages.channelId))
      .where(eq(messages.id, raw))
      .limit(1);
    const row = rows[0];
    if (!row) return fail(c, 403, "forbidden");

    const membershipRows = await db
      .select()
      .from(workspaceMembers)
      .where(
        and(
          eq(workspaceMembers.workspaceId, row.channel.workspaceId),
          eq(workspaceMembers.userId, session.user.id),
        ),
      )
      .limit(1);
    const membership = membershipRows[0];
    if (!membership) return fail(c, 403, "forbidden");

    if (row.channel.kind !== "public") {
      const memberRows = await db
        .select({ id: channelMembers.id })
        .from(channelMembers)
        .where(
          and(
            eq(channelMembers.channelId, row.channel.id),
            eq(channelMembers.userId, session.user.id),
          ),
        )
        .limit(1);
      if (!memberRows[0]) return fail(c, 403, "forbidden");
    }

    c.set("message", row.message);
    c.set("channel", row.channel);
    c.set("workspaceId", row.channel.workspaceId);
    c.set("membership", membership);
    await next();
  };
}

/**
 * Only the message's author may edit (or delete, with allowAdmin) the message.
 * Runs after requireMessageAccess — author comes from the loaded row, which was
 * written from the session only.
 */
export function requireMessageAuthor(
  options: { allowAdmin?: boolean } = {},
): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const session = c.get("session");
    if (!session) return fail(c, 401, "unauthorized");
    const message = c.get("message");
    if (!message) return fail(c, 403, "forbidden");
    if (message.authorId === session.user.id) {
      await next();
      return;
    }
    const membership = c.get("membership");
    if (options.allowAdmin && membership && roleAtLeast(membership.role, "admin")) {
      await next();
      return;
    }
    return fail(c, 403, "forbidden");
  };
}
