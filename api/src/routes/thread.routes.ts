/**
 * Thread routes: read a thread (parent + replies) and post replies.
 *
 * Replying to a reply normalizes to the thread ROOT, so every thread is one
 * level deep (Slack-style). Access is inherited from the parent message via
 * requireMessageAccess — outsiders get 403 with zero information leakage.
 */
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireMessageAccess } from "../auth/middleware";
import { LIMITS } from "../config";
import type { AppContext, AppEnv } from "../context";
import { decodeCursor, encodeCursor, fail, ok, readJson } from "../http";
import { parseLimitQuery } from "./channel.routes";
import { EVENTS, publishEvent, targets } from "../realtime/publish";
import { recordActivity } from "../services/activity";
import {
  createMessage,
  enrichMessages,
  getMessageById,
  listThreadReplies,
} from "../services/messages";

const replySchema = z.object({
  content: z
    .string()
    .min(1, "content is required")
    .max(LIMITS.messageChars, `message exceeds ${LIMITS.messageChars} characters`)
    .refine((v) => v.trim().length > 0, "message cannot be only whitespace"),
  attachments: z
    .array(
      z.object({
        storageKey: z.string().min(1).max(512),
        mimeType: z.string().max(100).optional(),
        sizeBytes: z.number().int().min(1),
        originalName: z.string().max(255).optional(),
      }),
    )
    .max(LIMITS.attachmentsPerMessage)
    .optional(),
});

export function threadRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db, bus } = ctx;
  const app = new Hono<AppEnv>();

  // --- read thread ----------------------------------------------------------
  app.get("/api/messages/:messageId/replies", requireAuth, requireMessageAccess(), async (c) => {
    const message = c.get("message");
    // normalize: replies of a reply belong to the same root thread
    const rootId = message.threadParentId ?? message.id;

    const limit = parseLimitQuery(c.req.query("limit"));
    if (limit === null) return fail(c, 400, "invalid limit (expected integer 1-100)");

    const cursorRaw = c.req.query("cursor");
    let cursor: ReturnType<typeof decodeCursor> = null;
    if (cursorRaw) {
      cursor = decodeCursor(cursorRaw);
      if (!cursor) return fail(c, 400, "invalid cursor");
    }

    const root = rootId === message.id ? message : await getMessageById(db, rootId);
    const { rows, hasMore } = await listThreadReplies(db, { rootId, cursor, limit });
    const [parentView] = root ? await enrichMessages(db, [root]) : [null];
    const replyViews = await enrichMessages(db, rows);
    const last = rows[rows.length - 1];
    const nextCursor = hasMore && last ? encodeCursor(last.createdAt, last.id) : null;

    return ok(c, {
      parent: parentView ?? null,
      replies: replyViews,
      nextCursor,
      hasMore,
    });
  });

  // --- post reply -----------------------------------------------------------
  app.post("/api/messages/:messageId/replies", requireAuth, requireMessageAccess(), async (c) => {
    const body = await readJson(c, replySchema);
    if (body.error) return body.error;
    const message = c.get("message");
    const channel = c.get("channel");
    const session = c.get("session");
    if (channel.archived) return fail(c, 400, "channel is archived");
    if (message.deletedAt) return fail(c, 400, "message has been deleted");

    const attachmentList = body.value.attachments ?? [];
    for (const attachment of attachmentList) {
      if (!attachment.storageKey.startsWith(`uploads/${session.user.id}/`)) {
        return fail(c, 400, "attachment storage key does not belong to the uploader");
      }
    }

    const rootId = message.threadParentId ?? message.id;
    const { row } = await createMessage(db, {
      channelId: channel.id,
      authorId: session.user.id,
      content: body.value.content,
      threadParentId: rootId,
      attachments: attachmentList,
    });
    const [view] = await enrichMessages(db, [row]);

    await publishEvent(bus, targets.channel(channel.id), EVENTS.MESSAGE_CREATED, {
      id: row.id,
      channelId: channel.id,
      workspaceId: channel.workspaceId,
      authorId: row.authorId,
      threadParentId: row.threadParentId,
      content: row.content,
      createdAt: row.createdAt.toISOString(),
    });

    // notify the thread starter (recordActivity skips self-notifications)
    const root = await getMessageById(db, rootId);
    if (root?.authorId) {
      await recordActivity(db, bus, {
        userId: root.authorId,
        actorId: session.user.id,
        type: "thread.reply",
        channelId: channel.id,
        kind: "thread",
        payload: { messageId: row.id, threadId: rootId, preview: row.content.slice(0, 120) },
      });
    }

    return ok(c, { reply: view }, 201);
  });

  return app;
}
