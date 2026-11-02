/**
 * Pin routes: pin/unpin messages, list pinned messages for a channel.
 * Every route requires channel membership (requireChannelMember).
 */
import { and, desc, eq, isNull } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireChannelMember } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { messages, pins } from "../db/schema";
import { fail, isUuid, ok, readJson } from "../http";
import { EVENTS, publishEvent, targets } from "../realtime/publish";
import { recordActivity } from "../services/activity";

const pinSchema = z.object({
  messageId: z.string().min(1).max(64),
});

export function pinRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db, bus } = ctx;
  const app = new Hono<AppEnv>();

  // --- list pins ------------------------------------------------------------
  app.get("/api/channels/:channelId/pins", requireAuth, requireChannelMember(), async (c) => {
    const channel = c.get("channel");
    const rows = await db
      .select({
        id: pins.id,
        messageId: pins.messageId,
        pinnedBy: pins.pinnedBy,
        createdAt: pins.createdAt,
        content: messages.content,
        authorId: messages.authorId,
        messageCreatedAt: messages.createdAt,
      })
      .from(pins)
      .innerJoin(messages, eq(messages.id, pins.messageId))
      .where(and(eq(pins.channelId, channel.id), isNull(messages.deletedAt)))
      .orderBy(desc(pins.createdAt));

    return ok(c, {
      pins: rows.map((r) => ({
        id: r.id,
        messageId: r.messageId,
        pinnedBy: r.pinnedBy,
        pinnedAt: r.createdAt.toISOString(),
        message: {
          id: r.messageId,
          channelId: channel.id,
          authorId: r.authorId,
          content: r.content,
          createdAt: r.messageCreatedAt.toISOString(),
        },
      })),
    });
  });

  // --- pin ------------------------------------------------------------------
  app.post("/api/channels/:channelId/pins", requireAuth, requireChannelMember(), async (c) => {
    const body = await readJson(c, pinSchema);
    if (body.error) return body.error;
    const channel = c.get("channel");
    const session = c.get("session");
    const messageId = body.value.messageId;
    if (!isUuid(messageId)) return fail(c, 400, "invalid message id");

    const messageRows = await db
      .select({ id: messages.id, authorId: messages.authorId, content: messages.content })
      .from(messages)
      .where(
        and(
          eq(messages.id, messageId),
          eq(messages.channelId, channel.id),
          isNull(messages.deletedAt),
        ),
      )
      .limit(1);
    // unknown or foreign message id: same answer, no cross-channel probing
    const message = messageRows[0];
    if (!message) return fail(c, 404, "message not found");

    const inserted = await db
      .insert(pins)
      .values({ channelId: channel.id, messageId, pinnedBy: session.user.id })
      .onConflictDoNothing()
      .returning({ id: pins.id, createdAt: pins.createdAt });
    const created = inserted.length > 0;
    const pinRow = inserted[0];

    await publishEvent(bus, targets.channel(channel.id), EVENTS.PIN_CHANGED, {
      messageId,
      channelId: channel.id,
      pinnedBy: session.user.id,
      pinned: true,
    });

    if (created && message.authorId) {
      await recordActivity(db, bus, {
        userId: message.authorId,
        actorId: session.user.id,
        type: "message.pinned",
        channelId: channel.id,
        kind: "pin",
        payload: { messageId, preview: message.content.slice(0, 120) },
      });
    }

    return ok(
      c,
      {
        pin: {
          id: pinRow?.id ?? null,
          messageId,
          pinnedBy: session.user.id,
          pinnedAt: pinRow?.createdAt.toISOString() ?? null,
        },
        created,
      },
      created ? 201 : 200,
    );
  });

  // --- unpin ----------------------------------------------------------------
  app.delete("/api/channels/:channelId/pins", requireAuth, requireChannelMember(), async (c) => {
    const body = await readJson(c, pinSchema);
    if (body.error) return body.error;
    const channel = c.get("channel");
    const session = c.get("session");
    const messageId = body.value.messageId;
    if (!isUuid(messageId)) return fail(c, 400, "invalid message id");

    const inChannel = await db
      .select({ id: messages.id })
      .from(messages)
      .where(and(eq(messages.id, messageId), eq(messages.channelId, channel.id)))
      .limit(1);
    if (!inChannel[0]) return fail(c, 404, "message not found");

    const removedRows = await db
      .delete(pins)
      .where(and(eq(pins.channelId, channel.id), eq(pins.messageId, messageId)))
      .returning({ id: pins.id });
    const removed = removedRows.length > 0;

    if (removed) {
      await publishEvent(bus, targets.channel(channel.id), EVENTS.PIN_CHANGED, {
        messageId,
        channelId: channel.id,
        pinnedBy: session.user.id,
        pinned: false,
      });
    }

    return ok(c, { messageId, removed });
  });

  return app;
}
