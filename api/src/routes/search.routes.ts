/**
 * Search: Postgres full-text (tsquery) for messages, case-insensitive name
 * matching for channels and people — all strictly scoped to what the caller
 * may see (IDOR-safe: another workspace's messages can never appear).
 *
 * GET /api/search?q=fox&scope=all|messages|channels|people
 */
import { and, eq, inArray, ne, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth } from "../auth/middleware";
import { LIMITS } from "../config";
import type { AppContext, AppEnv } from "../context";
import { resultRows } from "../db/client";
import { channelMembers, channels, workspaceMembers } from "../db/schema";
import { fail, ok } from "../http";

const searchSchema = z.object({
  q: z
    .string()
    .trim()
    .min(1, "q is required")
    .max(LIMITS.searchChars, `q exceeds ${LIMITS.searchChars} characters`),
  scope: z.enum(["all", "messages", "channels", "people"]).default("all"),
});

const GROUP_LIMIT = 20;
const NO_CHANNEL = "00000000-0000-0000-0000-000000000000";

function escapeLike(value: string): string {
  return `%${value.replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`;
}

export function searchRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db } = ctx;
  const app = new Hono<AppEnv>();

  app.get("/api/search", requireAuth, async (c) => {
    const query = c.req.query("q") ?? "";
    const scopeRaw = c.req.query("scope") ?? "all";
    const parsed = searchSchema.safeParse({ q: query, scope: scopeRaw });
    if (!parsed.success) {
      const first = parsed.error.issues[0];
      return fail(c, 400, `validation failed: ${first?.path.join(".") || "q"}: ${first?.message ?? "invalid"}`);
    }
    const { q, scope } = parsed.data;
    const userId = c.get("userId");

    // Everything I can see: workspaces I'm a member of + private/dm channels.
    const workspaceRows = await db
      .select({ workspaceId: workspaceMembers.workspaceId })
      .from(workspaceMembers)
      .where(eq(workspaceMembers.userId, userId));
    const myWorkspaces = workspaceRows.map((r) => r.workspaceId);

    const empty = { messages: [], channels: [], people: [] } as const;
    if (myWorkspaces.length === 0) {
      return ok(c, { query: q, scope, ...empty });
    }

    const channelRows = await db
      .select({ channelId: channelMembers.channelId })
      .from(channelMembers)
      .where(eq(channelMembers.userId, userId));
    const myChannels = channelRows.map((r) => r.channelId);

    const wantMessages = scope === "all" || scope === "messages";
    const wantChannels = scope === "all" || scope === "channels";
    const wantPeople = scope === "all" || scope === "people";

    const messagesResult = wantMessages
      ? resultRows<{
          id: string;
          channel_id: string;
          author_id: string | null;
          content: string;
          created_at: Date | string;
          channel_name: string | null;
        }>(
          await db.execute(sql`
          SELECT m.id, m.channel_id, m.author_id, m.content, m.created_at, c.name AS channel_name
          FROM messages m
          JOIN channels c ON c.id = m.channel_id
          WHERE m.deleted_at IS NULL
            AND to_tsvector('english', m.content) @@ websearch_to_tsquery('english', ${q})
            AND c.workspace_id IN (${sql.join(myWorkspaces.map((id) => sql`${id}`), sql`, `)})
            AND (c.kind = 'public' OR c.id IN (${sql.join(
              myChannels.length > 0 ? myChannels.map((id) => sql`${id}`) : [sql`${NO_CHANNEL}`],
              sql`, `,
            )}))
          ORDER BY ts_rank(to_tsvector('english', m.content), websearch_to_tsquery('english', ${q})) DESC,
                   m.created_at DESC
          LIMIT ${GROUP_LIMIT}`),
        )
      : null;

    const channelsResult = wantChannels
      ? await db
          .select({
            id: channels.id,
            name: channels.name,
            topic: channels.topic,
            kind: channels.kind,
            workspaceId: channels.workspaceId,
          })
          .from(channels)
          .where(
            and(
              inArray(channels.workspaceId, myWorkspaces),
              ne(channels.kind, "dm"),
              sql`(${channels.name} ILIKE ${escapeLike(q)} OR ${channels.topic} ILIKE ${escapeLike(q)})`,
            ),
          )
          .orderBy(channels.name)
          .limit(GROUP_LIMIT)
      : null;

    const peopleResult = wantPeople
      ? resultRows<{ id: string; name: string; email: string; image: string | null }>(
          await db.execute(sql`
          SELECT DISTINCT u.id, u.name, u.email, u.image
          FROM users u
          JOIN workspace_members wm ON wm.user_id = u.id
          WHERE wm.workspace_id IN (${sql.join(myWorkspaces.map((id) => sql`${id}`), sql`, `)})
            AND (u.name ILIKE ${escapeLike(q)} OR u.email ILIKE ${escapeLike(q)})
          ORDER BY u.name
          LIMIT ${GROUP_LIMIT}`),
        )
      : null;

    return ok(c, {
      query: q,
      scope,
      messages: wantMessages
        ? (messagesResult ?? []).map((m) => ({
            id: m.id,
            channelId: m.channel_id,
            authorId: m.author_id,
            content: m.content.slice(0, 400),
            channelName: m.channel_name,
            createdAt: new Date(m.created_at).toISOString(),
          }))
        : [],
      channels: wantChannels
        ? (channelsResult ?? []).map((ch) => ({
            id: ch.id,
            name: ch.name,
            topic: ch.topic,
            kind: ch.kind,
            workspaceId: ch.workspaceId,
          }))
        : [],
      people: wantPeople
        ? (peopleResult ?? []).map((p) => ({ id: p.id, name: p.name, email: p.email, image: p.image }))
        : [],
    });
  });

  return app;
}
