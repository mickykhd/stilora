/**
 * Direct-message routes.
 *
 *  - GET  /api/dm/conversations                     → my DM conversations
 *  - POST /api/workspaces/:workspaceId/dm/conversations {userId} → open/find
 *    a 1:1 conversation (workspace membership required — the channel sits
 *    under the workspace path so requireWorkspaceMember applies unchanged)
 *  - GET/POST /api/dm/conversations/:channelId/messages
 *
 * DM channels are kind='dm': access requires a channel_members row even
 * though the workspace is also verified (requireChannelMember does both).
 */
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireChannelMember, requireWorkspaceMember } from "../auth/middleware";
import { LIMITS } from "../config";
import type { AppContext, AppEnv } from "../context";
import { resultRows } from "../db/client";
import { channelMembers, channels, messages, users, workspaceMembers } from "../db/schema";
import { decodeCursor, encodeCursor, fail, isSafeId, ok, readJson } from "../http";
import { parseLimitQuery } from "./channel.routes";
import { EVENTS, publishEvent, targets } from "../realtime/publish";
import { recordActivity } from "../services/activity";
import { createMessage, enrichMessages, listChannelRootMessages } from "../services/messages";

const startConversationSchema = z.object({
  userId: z.string().min(1).max(64),
});

const sendMessageSchema = z.object({
  content: z
    .string()
    .min(1, "content is required")
    .max(LIMITS.messageChars, `message exceeds ${LIMITS.messageChars} characters`)
    .refine((v) => v.trim().length > 0, "message cannot be only whitespace"),
});

export function dmRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db, bus } = ctx;
  const app = new Hono<AppEnv>();

  // --- my conversations -----------------------------------------------------
  app.get("/api/dm/conversations", requireAuth, async (c) => {
    const userId = c.get("userId");

    const rows = await db
      .select({
        channel: channels,
        lastReadMessageId: channelMembers.lastReadMessageId,
      })
      .from(channelMembers)
      .innerJoin(channels, eq(channels.id, channelMembers.channelId))
      .where(and(eq(channelMembers.userId, userId), eq(channels.kind, "dm")));

    if (rows.length === 0) return ok(c, { conversations: [] });

    const channelIds = rows.map((r) => r.channel.id);

    // members + last activity per conversation (two batched queries)
    const memberRows = await db
      .select({
        channelId: channelMembers.channelId,
        userId: users.id,
        name: users.name,
        email: users.email,
        image: users.image,
      })
      .from(channelMembers)
      .innerJoin(users, eq(users.id, channelMembers.userId))
      .where(inArray(channelMembers.channelId, channelIds));

    // newest non-deleted message per conversation (window function, one round-trip)
    const lastRows = resultRows<{
      channel_id: string;
      content: string;
      created_at: Date | string;
    }>(
      await db.execute(sql`
      SELECT channel_id, content, created_at FROM (
        SELECT channel_id, content, created_at,
               row_number() OVER (PARTITION BY channel_id ORDER BY created_at DESC) AS rn
        FROM messages
        WHERE deleted_at IS NULL AND channel_id IN (${sql.join(channelIds.map((id) => sql`${id}`), sql`, `)})
      ) ranked
      WHERE rn = 1`),
    );

    const membersByChannel = new Map<string, Array<{ id: string; name: string; email: string; image: string | null }>>();
    for (const m of memberRows) {
      const list = membersByChannel.get(m.channelId) ?? [];
      list.push({ id: m.userId, name: m.name, email: m.email, image: m.image });
      membersByChannel.set(m.channelId, list);
    }
    const lastByChannel = new Map<string, { content: string; createdAt: Date }>();
    for (const raw of lastRows) {
      lastByChannel.set(raw.channel_id, {
        content: raw.content,
        createdAt: new Date(raw.created_at),
      });
    }

    const conversations = rows
      .map((r) => {
        const last = lastByChannel.get(r.channel.id);
        return {
          id: r.channel.id,
          workspaceId: r.channel.workspaceId,
          kind: r.channel.kind,
          createdAt: r.channel.createdAt.toISOString(),
          members: (membersByChannel.get(r.channel.id) ?? []).filter((m) => m.id !== userId),
          lastMessageAt: last ? last.createdAt.toISOString() : null,
          lastMessagePreview: last ? last.content.slice(0, 120) : null,
          lastReadMessageId: r.lastReadMessageId,
        };
      })
      .sort((a, b) => (b.lastMessageAt ?? "").localeCompare(a.lastMessageAt ?? ""));

    return ok(c, { conversations });
  });

  // --- open (or find) a 1:1 conversation ------------------------------------
  app.post(
    "/api/workspaces/:workspaceId/dm/conversations",
    requireAuth,
    requireWorkspaceMember(),
    async (c) => {
      const body = await readJson(c, startConversationSchema);
      if (body.error) return body.error;
      const workspaceId = c.get("workspaceId");
      const me = c.get("userId");
      const other = body.value.userId;

      if (!isSafeId(other)) return fail(c, 400, "invalid user id");
      if (other === me) return fail(c, 400, "cannot start a conversation with yourself");

      const otherMembership = await db
        .select({ id: workspaceMembers.id })
        .from(workspaceMembers)
        .where(
          and(
            eq(workspaceMembers.workspaceId, workspaceId),
            eq(workspaceMembers.userId, other),
          ),
        )
        .limit(1);
      if (!otherMembership[0]) return fail(c, 400, "user is not a member of this workspace");

      // deterministic de-dup: any existing dm channel containing BOTH users
      const existing = resultRows<{ id: string }>(
        await db.execute(sql`
        SELECT c.id FROM channels c
        WHERE c.workspace_id = ${workspaceId} AND c.kind = 'dm'
          AND EXISTS (SELECT 1 FROM channel_members cm WHERE cm.channel_id = c.id AND cm.user_id = ${me})
          AND EXISTS (SELECT 1 FROM channel_members cm WHERE cm.channel_id = c.id AND cm.user_id = ${other})
        LIMIT 1`),
      );

      const existingRow = existing[0];
      if (existingRow) {
        const conversation = await loadConversation(db, existingRow.id, me);
        return ok(c, { conversation, created: false });
      }

      const channel = await db.transaction(async (tx) => {
        const inserted = await tx
          .insert(channels)
          .values({ workspaceId, name: null, kind: "dm", createdBy: me })
          .returning();
        const row = inserted[0];
        if (!row) throw new Error("dm channel insert returned no row");
        await tx.insert(channelMembers).values([
          { channelId: row.id, userId: me },
          { channelId: row.id, userId: other },
        ]);
        return row;
      });

      const conversation = await loadConversation(db, channel.id, me);
      return ok(c, { conversation, created: true }, 201);
    },
  );

  // --- conversation messages ------------------------------------------------
  app.get(
    "/api/dm/conversations/:channelId/messages",
    requireAuth,
    requireChannelMember(),
    async (c) => {
      const channel = c.get("channel");
      if (channel.kind !== "dm") return fail(c, 400, "not a direct message channel");

      const limit = parseLimitQuery(c.req.query("limit"));
      if (limit === null) return fail(c, 400, "invalid limit (expected integer 1-100)");
      const cursorRaw = c.req.query("cursor");
      let cursor: ReturnType<typeof decodeCursor> = null;
      if (cursorRaw) {
        cursor = decodeCursor(cursorRaw);
        if (!cursor) return fail(c, 400, "invalid cursor");
      }

      const { rows, hasMore } = await listChannelRootMessages(db, {
        channelId: channel.id,
        cursor,
        limit,
      });
      const views = await enrichMessages(db, rows);
      const last = rows[rows.length - 1];
      const nextCursor = hasMore && last ? encodeCursor(last.createdAt, last.id) : null;
      return ok(c, { messages: views, nextCursor, hasMore });
    },
  );

  app.post(
    "/api/dm/conversations/:channelId/messages",
    requireAuth,
    requireChannelMember(),
    async (c) => {
      const channel = c.get("channel");
      if (channel.kind !== "dm") return fail(c, 400, "not a direct message channel");
      const body = await readJson(c, sendMessageSchema);
      if (body.error) return body.error;
      const session = c.get("session");

      const { row } = await createMessage(db, {
        channelId: channel.id,
        authorId: session.user.id,
        content: body.value.content,
      });
      const [view] = await enrichMessages(db, [row]);

      await publishEvent(bus, targets.channel(channel.id), EVENTS.MESSAGE_CREATED, {
        id: row.id,
        channelId: channel.id,
        workspaceId: channel.workspaceId,
        authorId: row.authorId,
        threadParentId: null,
        content: row.content,
        createdAt: row.createdAt.toISOString(),
      });

      // notify the other participant(s) of the DM
      const memberRows = await db
        .select({ userId: channelMembers.userId })
        .from(channelMembers)
        .where(eq(channelMembers.channelId, channel.id));
      for (const member of memberRows) {
        await recordActivity(db, bus, {
          userId: member.userId,
          actorId: session.user.id,
          type: "dm.message",
          channelId: channel.id,
          kind: "dm",
          payload: { messageId: row.id, preview: row.content.slice(0, 120) },
        });
      }

      return ok(c, { message: view }, 201);
    },
  );

  return app;
}

/** Assemble a conversation DTO (channel + members + last message preview). */
async function loadConversation(
  db: AppContext["db"],
  channelId: string,
  viewerId: string,
): Promise<Record<string, unknown>> {
  const channelRows = await db.select().from(channels).where(eq(channels.id, channelId)).limit(1);
  const channel = channelRows[0];
  if (!channel) return { id: channelId };

  const memberRows = await db
    .select({ userId: users.id, name: users.name, email: users.email, image: users.image })
    .from(channelMembers)
    .innerJoin(users, eq(users.id, channelMembers.userId))
    .where(eq(channelMembers.channelId, channelId));

  const lastRows = await db
    .select({
      content: messages.content,
      createdAt: messages.createdAt,
      authorId: messages.authorId,
    })
    .from(messages)
    .where(and(eq(messages.channelId, channelId), isNull(messages.deletedAt)))
    .orderBy(sql`${messages.createdAt} DESC`)
    .limit(1);

  const last = lastRows[0];
  return {
    id: channel.id,
    workspaceId: channel.workspaceId,
    kind: channel.kind,
    createdAt: channel.createdAt.toISOString(),
    members: memberRows
      .map((m) => ({ id: m.userId, name: m.name, email: m.email, image: m.image }))
      .filter((m) => m.id !== viewerId),
    lastMessageAt: last ? last.createdAt.toISOString() : null,
    lastMessagePreview: last ? last.content.slice(0, 120) : null,
  };
}
