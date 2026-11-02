/**
 * Typed realtime events.
 *
 * Every event the API publishes goes through publishEvent() so the event names
 * and payload shapes stay in one place (both server and future client SDKs can
 * share them).
 */
import type { EventBus } from "../events/bus";

export const EVENTS = {
  MESSAGE_CREATED: "message.created",
  MESSAGE_UPDATED: "message.updated",
  MESSAGE_DELETED: "message.deleted",
  REACTION_CHANGED: "reaction.changed",
  PIN_CHANGED: "pin.changed",
  TYPING: "typing",
  PRESENCE: "presence",
  UNREAD_BUMPED: "unread.bumped",
  VOICE_STATE: "voice.state",
} as const;

export type EventName = (typeof EVENTS)[keyof typeof EVENTS];

export interface EventMessagePayload {
  id: string;
  channelId: string;
  workspaceId: string;
  authorId: string | null;
  threadParentId: string | null;
  content: string;
  createdAt: string;
  editedAt?: string | null;
}

export interface EventReactionPayload {
  messageId: string;
  channelId: string;
  userId: string;
  emoji: string;
}

export interface EventPinPayload {
  messageId: string;
  channelId: string;
  pinnedBy: string;
  /** true when pinned, false when unpinned. */
  pinned: boolean;
}

export interface EventTypingPayload {
  channelId: string;
  userId: string;
}

export interface EventPresencePayload {
  channelId: string;
  userId: string;
  state: "online" | "offline";
}

export interface EventUnreadPayload {
  userId: string;
  channelId: string;
  kind: "dm" | "mention" | "thread" | "reaction" | "pin" | "workspace";
}

export interface EventVoiceStatePayload {
  room: string;
  channelId: string;
  participants: number;
  changedBy: string;
}

export interface EventPayloadMap {
  [EVENTS.MESSAGE_CREATED]: EventMessagePayload;
  [EVENTS.MESSAGE_UPDATED]: EventMessagePayload;
  [EVENTS.MESSAGE_DELETED]: { id: string; channelId: string; workspaceId: string };
  [EVENTS.REACTION_CHANGED]: EventReactionPayload;
  [EVENTS.PIN_CHANGED]: EventPinPayload;
  [EVENTS.TYPING]: EventTypingPayload;
  [EVENTS.PRESENCE]: EventPresencePayload;
  [EVENTS.UNREAD_BUMPED]: EventUnreadPayload;
  [EVENTS.VOICE_STATE]: EventVoiceStatePayload;
}

/** Target helpers — keep channel names consistent between pub and sub. */
export const targets = {
  channel: (channelId: string) => `channel:${channelId}`,
  workspace: (workspaceId: string) => `workspace:${workspaceId}`,
  user: (userId: string) => `user:${userId}`,
} as const;

export async function publishEvent<K extends EventName>(
  bus: EventBus,
  target: string,
  name: K,
  payload: EventPayloadMap[K],
): Promise<void> {
  await bus.publish(target, name, payload);
}
