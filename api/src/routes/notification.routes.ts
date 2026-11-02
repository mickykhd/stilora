/**
 * Notification routes: activity feed, mark-read, deep-work preferences.
 *
 * GET    /api/notifications            → feed + unread count
 * POST   /api/notifications/read       → mark some/all as read
 * GET    /api/notifications/prefs      → preferences (defaults, no write)
 * PUT    /api/notifications/prefs      → upsert deep-work / DND window
 */
import { and, desc, eq, inArray, isNull, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { requireAuth } from "../auth/middleware";
import type { AppContext, AppEnv } from "../context";
import { activity, notificationPrefs } from "../db/schema";
import { decodeCursor, encodeCursor, fail, isUuid, ok, readJson } from "../http";
import { DEFAULT_PREFS, normalizeHhmm } from "../services/activity";

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

const readSchema = z.object({
  ids: z.array(z.string().min(1).max(64)).max(100).optional(),
});

const prefsSchema = z
  .object({
    deepWorkEnabled: z.boolean().optional(),
    dndStart: z.string().regex(TIME_RE, "dndStart must be HH:MM between 00:00 and 23:59").optional(),
    dndEnd: z.string().regex(TIME_RE, "dndEnd must be HH:MM between 00:00 and 23:59").optional(),
  })
  .refine((v) => v.deepWorkEnabled !== undefined || v.dndStart !== undefined || v.dndEnd !== undefined, {
    message: "at least one field is required",
  });

function parseFeedLimit(raw: string | undefined): number | null {
  if (raw === undefined) return 20;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 50) return null;
  return value;
}

export function notificationRoutes(ctx: AppContext): Hono<AppEnv> {
  const { db } = ctx;
  const app = new Hono<AppEnv>();

  // --- activity feed --------------------------------------------------------
  app.get("/api/notifications", requireAuth, async (c) => {
    const userId = c.get("userId");
    const limit = parseFeedLimit(c.req.query("limit"));
    if (limit === null) return fail(c, 400, "invalid limit (expected integer 1-50)");

    const unreadOnly = ["1", "true"].includes(c.req.query("unreadOnly") ?? "");
    const cursorRaw = c.req.query("cursor");
    let cursor: ReturnType<typeof decodeCursor> = null;
    if (cursorRaw) {
      cursor = decodeCursor(cursorRaw);
      if (!cursor) return fail(c, 400, "invalid cursor");
    }

    const conditions = [eq(activity.userId, userId)];
    if (unreadOnly) conditions.push(isNull(activity.readAt));
    if (cursor) {
      conditions.push(
        sql`(${activity.createdAt}, ${activity.id}) < (${new Date(cursor.t)}, ${cursor.i})`,
      );
    }

    const [rows, unreadRows] = await Promise.all([
      db
        .select()
        .from(activity)
        .where(and(...conditions))
        .orderBy(desc(activity.createdAt), desc(activity.id))
        .limit(limit + 1),
      db
        .select({ count: sql<string>`count(*)::int` })
        .from(activity)
        .where(and(eq(activity.userId, userId), isNull(activity.readAt))),
    ]);

    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const last = page[page.length - 1];
    const nextCursor = hasMore && last ? encodeCursor(last.createdAt, last.id) : null;

    return ok(c, {
      notifications: page.map((row) => ({
        id: row.id,
        type: row.type,
        payload: row.payload,
        readAt: row.readAt ? row.readAt.toISOString() : null,
        createdAt: row.createdAt.toISOString(),
      })),
      unreadCount: Number(unreadRows[0]?.count ?? 0),
      nextCursor,
      hasMore,
    });
  });

  // --- mark read ------------------------------------------------------------
  app.post("/api/notifications/read", requireAuth, async (c) => {
    const body = await readJson(c, readSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");

    const ids = body.value.ids;
    if (ids) {
      for (const id of ids) {
        if (!isUuid(id)) return fail(c, 400, "invalid notification id");
      }
    }

    const conditions = [eq(activity.userId, userId), isNull(activity.readAt)];
    if (ids && ids.length > 0) conditions.push(inArray(activity.id, ids));

    const updated = await db
      .update(activity)
      .set({ readAt: new Date() })
      .where(and(...conditions))
      .returning({ id: activity.id });

    return ok(c, { updated: updated.length });
  });

  // --- preferences ----------------------------------------------------------
  app.get("/api/notifications/prefs", requireAuth, async (c) => {
    const userId = c.get("userId");
    const rows = await db
      .select()
      .from(notificationPrefs)
      .where(eq(notificationPrefs.userId, userId))
      .limit(1);
    const pref = rows[0];

    return ok(c, {
      prefs: pref
        ? {
            userId: pref.userId,
            deepWorkEnabled: pref.deepWorkEnabled,
            dndStart: normalizeHhmm(pref.dndStart),
            dndEnd: normalizeHhmm(pref.dndEnd),
            updatedAt: pref.updatedAt.toISOString(),
          }
        : {
            userId,
            deepWorkEnabled: DEFAULT_PREFS.deepWorkEnabled,
            dndStart: DEFAULT_PREFS.dndStart,
            dndEnd: DEFAULT_PREFS.dndEnd,
            updatedAt: null,
          },
    });
  });

  app.put("/api/notifications/prefs", requireAuth, async (c) => {
    const body = await readJson(c, prefsSchema);
    if (body.error) return body.error;
    const userId = c.get("userId");
    const patch = body.value;

    // merge with existing (or defaults) so partial updates keep the other half
    const existingRows = await db
      .select()
      .from(notificationPrefs)
      .where(eq(notificationPrefs.userId, userId))
      .limit(1);
    const existing = existingRows[0];

    const next = {
      deepWorkEnabled: patch.deepWorkEnabled ?? existing?.deepWorkEnabled ?? DEFAULT_PREFS.deepWorkEnabled,
      dndStart: patch.dndStart ?? existing?.dndStart ?? DEFAULT_PREFS.dndStart,
      dndEnd: patch.dndEnd ?? existing?.dndEnd ?? DEFAULT_PREFS.dndEnd,
    };

    const inserted = await db
      .insert(notificationPrefs)
      .values({ userId, ...next, updatedAt: new Date() })
      .onConflictDoUpdate({
        target: notificationPrefs.userId,
        set: { ...next, updatedAt: new Date() },
      })
      .returning();

    const pref = inserted[0];
    if (!pref) return fail(c, 500, "internal server error");

    return ok(c, {
      prefs: {
        userId: pref.userId,
        deepWorkEnabled: pref.deepWorkEnabled,
        dndStart: normalizeHhmm(pref.dndStart),
        dndEnd: normalizeHhmm(pref.dndEnd),
        updatedAt: pref.updatedAt.toISOString(),
      },
    });
  });

  return app;
}
