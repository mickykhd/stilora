/**
 * Reaction routes: PUT adds (idempotent), DELETE removes.
 * Access is inherited from the message via requireMessageAccess.
 */
import { and, eq } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth, requireMessageAccess } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { reactions } from "../db/schema";
import { fail, ok, readJson } from "../http";
import { EVENTS, publishEvent, targets } from "../realtime/publish";
import { recordActivity } from "../services/activity";

const emojiSchema = z
  .string()
  .min(1, "emoji is required")
  .max(32, "emoji is too long")
  .refine((v) => v.trim() === v && !/\s/.test(v), "emoji must not contain whitespace")
  .refine(
    (v) => !/[\u0000-\u001f\u007f]/.test(v),
    "emoji must not contain control characters",
  );

const reactionSchema = z.object({ emoji: emojiSchema });

export function reactionRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db, bus } = ctx;
  const app = new Hono<AppEnv>();

  app.put("/api/messages/:messageId/reactions", requireAuth, requireMessageAccess(), async (c) => {
    const body = await readJson(c, reactionSchema);
    if (body.error) return body.error;
    const message = c.get("message");
    const channel = c.get("channel");
    const session = c.get("session");
    if (message.deletedAt) return fail(c, 400, "message has been deleted");

    const inserted = await db
      .insert(reactions)
      .values({ messageId: message.id, userId: session.user.id, emoji: body.value.emoji })
      .onConflictDoNothing()
      .returning({ id: reactions.id });
    const created = inserted.length > 0;

    if (created) {
      await publishEvent(bus, targets.channel(channel.id), EVENTS.REACTION_CHANGED, {
        messageId: message.id,
        channelId: channel.id,
        userId: session.user.id,
        emoji: body.value.emoji,
      });
      if (message.authorId) {
        await recordActivity(db, bus, {
          userId: message.authorId,
          actorId: session.user.id,
          type: "reaction.added",
          channelId: channel.id,
          kind: "reaction",
          payload: { messageId: message.id, emoji: body.value.emoji },
        });
      }
    }

    return ok(c, {
      reaction: { messageId: message.id, emoji: body.value.emoji },
      created,
    });
  });

  app.delete(
    "/api/messages/:messageId/reactions",
    requireAuth,
    requireMessageAccess(),
    async (c) => {
      const body = await readJson(c, reactionSchema);
      if (body.error) return body.error;
      const message = c.get("message");
      const channel = c.get("channel");
      const session = c.get("session");

      const removedRows = await db
        .delete(reactions)
        .where(
          and(
            eq(reactions.messageId, message.id),
            eq(reactions.userId, session.user.id),
            eq(reactions.emoji, body.value.emoji),
          ),
        )
        .returning({ id: reactions.id });
      const removed = removedRows.length > 0;

      if (removed) {
        await publishEvent(bus, targets.channel(channel.id), EVENTS.REACTION_CHANGED, {
          messageId: message.id,
          channelId: channel.id,
          userId: session.user.id,
          emoji: body.value.emoji,
        });
      }

      return ok(c, {
        reaction: { messageId: message.id, emoji: body.value.emoji },
        removed,
      });
    },
  );

  return app;
}
