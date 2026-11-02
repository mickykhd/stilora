/**
 * Activity feed (notifications) recording.
 *
 * Deep-work ("do not disturb") semantics: rows are ALWAYS recorded so the feed
 * stays complete, but when deep work is on and the clock is inside the hold
 * window, the realtime `unread.bumped` push is held back (payload.held = true)
 * and consumers should not deliver it until the window ends.
 */
import { eq } from "drizzle-orm";
import type { DB } from "../db/client";
import type { EventBus } from "../events/bus";
import { activity, notificationPrefs, type NotificationPref } from "../db/schema";
import { EVENTS, publishEvent, targets, type EventUnreadPayload } from "../realtime/publish";

export const DEFAULT_PREFS = {
  deepWorkEnabled: false,
  dndStart: "22:00",
  dndEnd: "07:00",
} as const;

function minutesOf(hhmm: string): number | null {
  // accepts HH:MM and the HH:MM:SS form Postgres `time` columns return
  const match = /^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$/.exec(hhmm);
  if (!match || !match[1] || !match[2]) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

/** Postgres `time` round-trips as HH:MM:SS — the API speaks plain HH:MM. */
export function normalizeHhmm(value: string): string {
  return value.slice(0, 5);
}

/**
 * Is `now` inside the deep-work window? Windows that wrap midnight
 * (e.g. 22:00 → 07:00) are supported; a zero-length window counts as off.
 * Clock comparisons use UTC so results are deterministic across machines.
 */
export function isInDeepWorkWindow(
  prefs: Pick<NotificationPref, "deepWorkEnabled" | "dndStart" | "dndEnd">,
  now: Date,
): boolean {
  if (!prefs.deepWorkEnabled) return false;
  const start = minutesOf(prefs.dndStart);
  const end = minutesOf(prefs.dndEnd);
  if (start === null || end === null || start === end) return false;
  const current = now.getUTCHours() * 60 + now.getUTCMinutes();
  if (start < end) return current >= start && current < end;
  return current >= start || current < end; // window wraps midnight
}

export interface RecordActivityInput {
  /** Recipient (notification target). */
  userId: string;
  /** Who caused it — self-actions never notify. */
  actorId: string;
  type: string;
  channelId: string;
  kind: EventUnreadPayload["kind"];
  payload: Record<string, unknown>;
}

/** Insert an activity row and (unless deep-work holds it) push unread.bumped. */
export async function recordActivity(
  db: DB,
  bus: EventBus,
  input: RecordActivityInput,
): Promise<string | null> {
  if (input.userId === input.actorId) return null;

  const prefsRows = await db
    .select()
    .from(notificationPrefs)
    .where(eq(notificationPrefs.userId, input.userId))
    .limit(1);
  const prefs = prefsRows[0] ?? DEFAULT_PREFS;
  const held = isInDeepWorkWindow(prefs, new Date());

  const inserted = await db
    .insert(activity)
    .values({
      userId: input.userId,
      type: input.type,
      payload: { ...input.payload, actorId: input.actorId, held },
    })
    .returning({ id: activity.id });

  if (!held) {
    await publishEvent(bus, targets.user(input.userId), EVENTS.UNREAD_BUMPED, {
      userId: input.userId,
      channelId: input.channelId,
      kind: input.kind,
    });
  }
  return inserted[0]?.id ?? null;
}
