/**
 * Channel routes: channel CRUD/membership/read-state, message list (cursor
 * pagination), message create/edit/delete.
 *
 * authorId / editedAt are ALWAYS taken from the session — client-supplied
 * identity fields are stripped by the zod schemas (objects strip unknown keys
 * by default), which security.test.ts asserts explicitly.
 */
import { and, eq, ne } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import {
  requireAuth,
  requireChannelMember,
  requireMessageAccess,
  requireMessageAuthor,
  requireWorkspaceMember,
  roleAtLeast,
} from "../auth/middleware";
import { LIMITS } from "../config";
import type { AppContext, AppEnv } from "../context";
import { isUniqueViolation } from "../db/client";
import { attachments, channelMembers, channels, messages, workspaceMembers } from "../db/schema";
import { decodeCursor, encodeCursor, fail, isSafeId, isUuid, ok, readJson } from "../http";
import { EVENTS, publishEvent, targets } from "../realtime/publish";
import { createMessage, enrichMessages, listChannelRootMessages } from "../services/messages";

const CHANNEL_NAME_RE = /^[a-z0-9][a-z0-9._-]{0,79}$/;

const contentSchema = z
  .string()
  .min(1, "content is required")
  .max(LIMITS.messageChars, `message exceeds ${LIMITS.messageChars} characters`)
  .refine((v) => v.trim().length > 0, "message cannot be only whitespace");

const attachmentSchema = z.object({
  storageKey: z.string().min(1).max(512),
  mimeType: z.string().max(100).optional(),
  sizeBytes: z.number().int().min(1),
  originalName: z.string().max(255).optional(),
});

const createMessageSchema = z.object({
  content: contentSchema,
  attachments: z.array(attachmentSchema).max(LIMITS.attachmentsPerMessage).optional(),
});

const editMessageSchema = z.object({
  content: contentSchema,
});

const createChannelSchema = z.object({
  name: z
    .string()
    .regex(CHANNEL_NAME_RE, "channel name must be lowercase letters, numbers, '.', '_' or '-'"),
  topic: z.string().max(255, "topic is too long").optional(),
  kind: z.enum(["public", "private"]).default("public"),
});

const patchChannelSchema = z.object({
  name: z
    .string()
    .regex(CHANNEL_NAME_RE, "channel name must be lowercase letters, numbers, '.', '_' or '-'")
    .optional(),
  topic: z.string().max(255, "topic is too long").nullable().optional(),
  archived: z.boolean().optional(),
});

const addMemberSchema = z.object({
  userId: z.string().min(1).max(64),
});

const readSchema = z.object({
  messageId: z.string().min(1).max(64),
});

/** Parse ?limit= — returns null when invalid. */
export function parseLimitQuery(raw: string | undefined): number | null {
  if (raw === undefined) return LIMITS.pageDefault;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > LIMITS.pageMax) return null;
  return value;
}

function publicChannelView(row: typeof channels.$inferSelect) {
  return {
    id: row.id,
    workspaceId: row.workspaceId,
    name: row.name,
    topic: row.topic,
    kind: row.kind,
    archived: row.archived,
    createdBy: row.createdBy,
    createdAt: row.createdAt.toISOString(),
  };
}

export function channelRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db, bus } = ctx;
  const app = new Hono<AppEnv>();

  // --- list channels --------------------------------------------------------
  app.get(
    "/api/workspaces/:workspaceId/channels",
    requireAuth,
    requireWorkspaceMember(),
    async (c) => {
      const workspaceId = c.get("workspaceId");
      const userId = c.get("userId");

      const rows = await db
        .select({
          channel: channels,
          memberRowId: channelMembers.id,
          lastReadMessageId: channelMembers.lastReadMessageId,
        })
        .from(channels)
        .leftJoin(
          channelMembers,
          and(eq(channelMembers.channelId, channels.id), eq(channelMembers.userId, userId)),
        )
        .where(and(eq(channels.workspaceId, workspaceId), ne(channels.kind, "dm")))
        .orderBy(channels.createdAt);

      // Private channels are invisible without a membership row — no
      // existence leak for channels I'm not part of.
      const visible = rows.filter((r) => r.channel.kind === "public" || r.memberRowId !== null);

      return ok(c, {
        channels: visible.map((r) => ({
          ...publicChannelView(r.channel),
          joined: r.memberRowId !== null,
          lastReadMessageId: r.lastReadMessageId,
        })),
      });
    },
  );

  // --- create channel -------------------------------------------------------
  app.post(
    "/api/workspaces/:workspaceId/channels",
    requireAuth,
    requireWorkspaceMember(),
    async (c) => {
      const body = await readJson(c, createChannelSchema);
      if (body.error) return body.error;
      const workspaceId = c.get("workspaceId");
      const userId = c.get("userId");

      try {
        const channel = await db.transaction(async (tx) => {
          const inserted = await tx
            .insert(channels)
            .values({
              workspaceId,
              name: body.value.name,
              topic: body.value.topic ?? null,
              kind: body.value.kind,
              createdBy: userId,
            })
            .returning();
          const row = inserted[0];
          if (!row) throw new Error("channel insert returned no row");
          await tx.insert(channelMembers).values({ channelId: row.id, userId });
          return row;
        });
        return ok(c, { channel: publicChannelView(channel) }, 201);
      } catch (err) {
        if (isUniqueViolation(err)) {
          return fail(c, 409, "channel name already exists in this workspace");
        }
        throw err;
      }
    },
  );

  // --- channel detail -------------------------------------------------------
  app.get("/api/channels/:channelId", requireAuth, requireChannelMember(), async (c) => {
    const channel = c.get("channel");
    const userId = c.get("userId");
    const memberRows = await db
      .select({ lastReadMessageId: channelMembers.lastReadMessageId })
      .from(channelMembers)
      .where(and(eq(channelMembers.channelId, channel.id), eq(channelMembers.userId, userId)))
      .limit(1);

    return ok(c, {
      channel: {
        ...publicChannelView(channel),
        lastReadMessageId: memberRows[0]?.lastReadMessageId ?? null,
      },
    });
  });

  // --- update channel (workspace admin+ or channel creator) -----------------
  app.patch("/api/channels/:channelId", requireAuth, requireChannelMember(), async (c) => {
    const session = c.get("session");
    const channel = c.get("channel");
    const membership = c.get("membership");
    if (!roleAtLeast(membership.role, "admin") && channel.createdBy !== session.user.id) {
      return fail(c, 403, "forbidden");
    }

    const body = await readJson(c, patchChannelSchema);
    if (body.error) return body.error;
    const patch = body.value;
    if (patch.name === undefined && patch.topic === undefined && patch.archived === undefined) {
      return fail(c, 400, "no fields to update");
    }

    try {
      const updated = await db
        .update(channels)
        .set({
          ...(patch.name !== undefined ? { name: patch.name } : {}),
          ...(patch.topic !== undefined ? { topic: patch.topic } : {}),
          ...(patch.archived !== undefined ? { archived: patch.archived } : {}),
          updatedAt: new Date(),
        })
        .where(eq(channels.id, channel.id))
        .returning();
      const row = updated[0];
      if (!row) return fail(c, 403, "forbidden");
      return ok(c, { channel: { ...publicChannelView(row), updatedAt: row.updatedAt.toISOString() } });
    } catch (err) {
      if (isUniqueViolation(err)) {
        return fail(c, 409, "channel name already exists in this workspace");
      }
      throw err;
    }
  });

  // --- add a workspace member to a channel ----------------------------------
  app.post("/api/channels/:channelId/members", requireAuth, requireChannelMember(), async (c) => {
    const session = c.get("session");
    const channel = c.get("channel");
    const membership = c.get("membership");
    if (!roleAtLeast(membership.role, "admin") && channel.createdBy !== session.user.id) {
      return fail(c, 403, "forbidden");
    }

    const body = await readJson(c, addMemberSchema);
    if (body.error) return body.error;
    if (!isSafeId(body.value.userId)) return fail(c, 400, "invalid user id");

    const targetInWorkspace = await db
      .select({ id: workspaceMembers.id })
      .from(workspaceMembers)
      .where(
        and(
          eq(workspaceMembers.workspaceId, channel.workspaceId),
          eq(workspaceMembers.userId, body.value.userId),
        ),
      )
      .limit(1);
    if (!targetInWorkspace[0]) return fail(c, 400, "user is not a member of this workspace");

    const inserted = await db
      .insert(channelMembers)
      .values({ channelId: channel.id, userId: body.value.userId })
      .onConflictDoNothing()
      .returning({ id: channelMembers.id });

    return ok(
      c,
      { channelId: channel.id, userId: body.value.userId, added: inserted.length > 0 },
      inserted.length > 0 ? 201 : 200,
    );
  });

  // --- mark channel read ----------------------------------------------------
  app.post("/api/channels/:channelId/read", requireAuth, requireChannelMember(), async (c) => {
    const body = await readJson(c, readSchema);
    if (body.error) return body.error;
    const channel = c.get("channel");
    const userId = c.get("userId");
    const messageId = body.value.messageId;
    if (!isUuid(messageId)) return fail(c, 400, "invalid message id");

    const rows = await db
      .select({ id: messages.id })
      .from(messages)
      .where(and(eq(messages.id, messageId), eq(messages.channelId, channel.id)))
      .limit(1);
    if (!rows[0]) return fail(c, 404, "message not found");

    await db
      .insert(channelMembers)
      .values({ channelId: channel.id, userId, lastReadMessageId: messageId })
      .onConflictDoUpdate({
        target: [channelMembers.channelId, channelMembers.userId],
        set: { lastReadMessageId: messageId, updatedAt: new Date() },
      });

    return ok(c, { channelId: channel.id, lastReadMessageId: messageId });
  });

  // --- list messages (cursor pagination) ------------------------------------
  app.get("/api/channels/:channelId/messages", requireAuth, requireChannelMember(), async (c) => {
    const channel = c.get("channel");
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
  });

  // --- post message ---------------------------------------------------------
  app.post("/api/channels/:channelId/messages", requireAuth, requireChannelMember(), async (c) => {
    const body = await readJson(c, createMessageSchema);
    if (body.error) return body.error;
    const channel = c.get("channel");
    const session = c.get("session");
    if (channel.archived) return fail(c, 400, "channel is archived");

    const attachmentList = body.value.attachments ?? [];
    for (const attachment of attachmentList) {
      if (!attachment.storageKey.startsWith(`uploads/${session.user.id}/`)) {
        return fail(c, 400, "attachment storage key does not belong to the uploader");
      }
    }

    // authorId comes from the session — never from the body.
    const { row } = await createMessage(db, {
      channelId: channel.id,
      authorId: session.user.id,
      content: body.value.content,
      attachments: attachmentList,
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

    return ok(c, { message: view }, 201);
  });

  // --- edit message (author only) ------------------------------------------
  app.patch(
    "/api/messages/:messageId",
    requireAuth,
    requireMessageAccess(),
    requireMessageAuthor(),
    async (c) => {
      const message = c.get("message");
      const channel = c.get("channel");
      if (message.deletedAt) return fail(c, 400, "message has been deleted");
      if (channel.archived) return fail(c, 400, "channel is archived");

      const body = await readJson(c, editMessageSchema);
      if (body.error) return body.error;

      const now = new Date();
      const updated = await db
        .update(messages)
        .set({ content: body.value.content, editedAt: now, updatedAt: now })
        .where(eq(messages.id, message.id))
        .returning();
      const row = updated[0];
      if (!row) return fail(c, 403, "forbidden");
      const [view] = await enrichMessages(db, [row]);

      await publishEvent(bus, targets.channel(channel.id), EVENTS.MESSAGE_UPDATED, {
        id: row.id,
        channelId: channel.id,
        workspaceId: channel.workspaceId,
        authorId: row.authorId,
        threadParentId: row.threadParentId,
        content: row.content,
        createdAt: row.createdAt.toISOString(),
        editedAt: row.editedAt?.toISOString() ?? null,
      });

      return ok(c, { message: view });
    },
  );

  // --- delete message (author, or workspace admin+) ------------------------
  app.delete(
    "/api/messages/:messageId",
    requireAuth,
    requireMessageAccess(),
    requireMessageAuthor({ allowAdmin: true }),
    async (c) => {
      const message = c.get("message");
      const channel = c.get("channel");

      if (message.deletedAt) {
        // idempotent: deleting twice is a no-op, not an error
        return ok(c, {
          message: {
            id: message.id,
            channelId: message.channelId,
            content: "",
            deletedAt: message.deletedAt.toISOString(),
          },
        });
      }

      const now = new Date();
      const row = await db.transaction(async (tx) => {
        const updated = await tx
          .update(messages)
          .set({ deletedAt: now, content: "", updatedAt: now })
          .where(eq(messages.id, message.id))
          .returning();
        await tx.delete(attachments).where(eq(attachments.messageId, message.id));
        return updated[0];
      });
      if (!row) return fail(c, 403, "forbidden");

      await publishEvent(bus, targets.channel(channel.id), EVENTS.MESSAGE_DELETED, {
        id: row.id,
        channelId: channel.id,
        workspaceId: channel.workspaceId,
      });

      return ok(c, {
        message: {
          id: row.id,
          channelId: row.channelId,
          content: "",
          deletedAt: row.deletedAt?.toISOString() ?? now.toISOString(),
        },
      });
    },
  );

  return app;
}
