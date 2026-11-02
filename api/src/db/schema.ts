/**
 * Drizzle schema for Hush (Postgres / Neon / local docker-compose / PGlite).
 *
 * Naming: snake_case columns, plural table names. Domain ids are uuid
 * (gen_random_uuid); Better Auth core tables keep text ids because Better Auth
 * generates them itself.
 *
 * Better Auth note: the drizzle adapter maps fields by drizzle *property*
 * name, so the auth tables keep camelCase properties (emailVerified, …) with
 * snake_case column names. See src/auth/auth.ts for the adapter wiring.
 */
import { sql } from "drizzle-orm";
import type { AnyPgColumn } from "drizzle-orm/pg-core";
import {
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  time,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

export const workspaceRoleEnum = pgEnum("workspace_role", ["owner", "admin", "member"]);
export const channelKindEnum = pgEnum("channel_kind", ["public", "private", "dm"]);

const ts = (name: string) => timestamp(name, { withTimezone: true });

// ---------------------------------------------------------------------------
// Better Auth core tables (standard schema — do not rename fields)
// ---------------------------------------------------------------------------

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: boolean("email_verified").notNull().default(false),
  image: text("image"),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

export const sessions = pgTable(
  "sessions",
  {
    id: text("id").primaryKey(),
    expiresAt: ts("expires_at").notNull(),
    token: text("token").notNull().unique(),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
    ipAddress: text("ip_address"),
    userAgent: text("user_agent"),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (t) => [index("sessions_user_id_idx").on(t.userId)],
);

export const accounts = pgTable(
  "accounts",
  {
    id: text("id").primaryKey(),
    accountId: text("account_id").notNull(),
    providerId: text("provider_id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    accessToken: text("access_token"),
    refreshToken: text("refresh_token"),
    idToken: text("id_token"),
    accessTokenExpiresAt: ts("access_token_expires_at"),
    refreshTokenExpiresAt: ts("refresh_token_expires_at"),
    scope: text("scope"),
    password: text("password"),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [index("accounts_user_id_idx").on(t.userId)],
);

export const verifications = pgTable("verifications", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: ts("expires_at").notNull(),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Workspaces & membership
// ---------------------------------------------------------------------------

export const workspaces = pgTable("workspaces", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  inviteCode: text("invite_code").notNull().unique(),
  createdAt: ts("created_at").notNull().defaultNow(),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

export const workspaceMembers = pgTable(
  "workspace_members",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    workspaceId: uuid("workspace_id")
      .notNull()
      .references(() => workspaces.id, { onDelete: "cascade" }),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    role: workspaceRoleEnum("role").notNull().default("member"),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("workspace_members_workspace_user_unique").on(t.workspaceId, t.userId),
    index("workspace_members_user_id_idx").on(t.userId),
  ],
);

// ---------------------------------------------------------------------------
// Channels (public/private/dm), messages, channel membership
// ---------------------------------------------------------------------------

export const channels = pgTable(
  "channels",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    workspaceId: uuid("workspace_id")
      .notNull()
      .references(() => workspaces.id, { onDelete: "cascade" }),
    // null for DM channels; required by validation for public/private ones.
    name: text("name"),
    topic: text("topic"),
    kind: channelKindEnum("kind").notNull().default("public"),
    archived: boolean("archived").notNull().default(false),
    createdBy: text("created_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [
    index("channels_workspace_id_idx").on(t.workspaceId),
    // One named channel per workspace; DMs (name null) are exempt.
    uniqueIndex("channels_workspace_name_unique")
      .on(t.workspaceId, t.name)
      .where(sql`kind <> 'dm' AND name IS NOT NULL`),
  ],
);

export const messages = pgTable(
  "messages",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    channelId: uuid("channel_id")
      .notNull()
      .references(() => channels.id, { onDelete: "cascade" }),
    // CASCADE: deleting an account removes the content that account authored.
    authorId: text("author_id").references(() => users.id, { onDelete: "cascade" }),
    // SET NULL: deleting a reply must not delete the parent thread.
    threadParentId: uuid("thread_parent_id").references(
      (): AnyPgColumn => messages.id,
      { onDelete: "set null" },
    ),
    content: text("content").notNull().default(""),
    editedAt: ts("edited_at"),
    deletedAt: ts("deleted_at"),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [
    index("messages_channel_created_at_idx").on(t.channelId, t.createdAt.desc()),
    // Partial index: only real thread replies carry a parent id.
    index("messages_thread_parent_idx")
      .on(t.threadParentId)
      .where(sql`thread_parent_id IS NOT NULL`),
    // Full-text search: expression GIN index; the partial predicate matches
    // the WHERE clause every search/list query uses (see search.routes.ts).
    index("messages_content_fts_idx")
      .using("gin", sql`to_tsvector('english', content)`)
      .where(sql`deleted_at IS NULL`),
  ],
);

export const channelMembers = pgTable(
  "channel_members",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    channelId: uuid("channel_id")
      .notNull()
      .references(() => channels.id, { onDelete: "cascade" }),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    lastReadMessageId: uuid("last_read_message_id").references(() => messages.id, {
      onDelete: "set null",
    }),
    createdAt: ts("created_at").notNull().defaultNow(),
    updatedAt: ts("updated_at").notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("channel_members_channel_user_unique").on(t.channelId, t.userId),
    index("channel_members_user_id_idx").on(t.userId),
  ],
);

export const attachments = pgTable(
  "attachments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    messageId: uuid("message_id")
      .notNull()
      .references(() => messages.id, { onDelete: "cascade" }),
    storageKey: text("storage_key").notNull(),
    mimeType: text("mime_type"),
    sizeBytes: integer("size_bytes").notNull(),
    originalName: text("original_name"),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [index("attachments_message_id_idx").on(t.messageId)],
);

// ---------------------------------------------------------------------------
// Reactions, pins, invites
// ---------------------------------------------------------------------------

export const reactions = pgTable(
  "reactions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    messageId: uuid("message_id")
      .notNull()
      .references(() => messages.id, { onDelete: "cascade" }),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    emoji: text("emoji").notNull(),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("reactions_message_user_emoji_unique").on(t.messageId, t.userId, t.emoji),
    index("reactions_message_id_idx").on(t.messageId),
  ],
);

export const pins = pgTable(
  "pins",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    channelId: uuid("channel_id")
      .notNull()
      .references(() => channels.id, { onDelete: "cascade" }),
    messageId: uuid("message_id")
      .notNull()
      .references(() => messages.id, { onDelete: "cascade" }),
    pinnedBy: text("pinned_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex("pins_channel_message_unique").on(t.channelId, t.messageId),
    index("pins_channel_id_idx").on(t.channelId),
  ],
);

export const invites = pgTable(
  "invites",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    workspaceId: uuid("workspace_id")
      .notNull()
      .references(() => workspaces.id, { onDelete: "cascade" }),
    email: text("email"),
    token: text("token").notNull().unique(),
    expiresAt: ts("expires_at").notNull(),
    acceptedAt: ts("accepted_at"),
    invitedBy: text("invited_by").references(() => users.id, { onDelete: "set null" }),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [index("invites_workspace_id_idx").on(t.workspaceId)],
);

// ---------------------------------------------------------------------------
// Notifications / activity
// ---------------------------------------------------------------------------

export const notificationPrefs = pgTable("notification_prefs", {
  userId: text("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  deepWorkEnabled: boolean("deep_work_enabled").notNull().default(false),
  dndStart: time("dnd_start").notNull().default("22:00"),
  dndEnd: time("dnd_end").notNull().default("07:00"),
  updatedAt: ts("updated_at").notNull().defaultNow(),
});

export const activity = pgTable(
  "activity",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: text("type").notNull(),
    payload: jsonb("payload").notNull().default(sql`'{}'::jsonb`),
    readAt: ts("read_at"),
    createdAt: ts("created_at").notNull().defaultNow(),
  },
  (t) => [
    index("activity_user_created_at_idx").on(t.userId, t.createdAt.desc()),
    // Fast unread-badge lookups.
    index("activity_user_unread_idx")
      .on(t.userId, t.createdAt.desc())
      .where(sql`read_at IS NULL`),
  ],
);

export type User = typeof users.$inferSelect;
export type Session = typeof sessions.$inferSelect;
export type Account = typeof accounts.$inferSelect;
export type Verification = typeof verifications.$inferSelect;
export type Workspace = typeof workspaces.$inferSelect;
export type WorkspaceMember = typeof workspaceMembers.$inferSelect;
export type Channel = typeof channels.$inferSelect;
export type ChannelMember = typeof channelMembers.$inferSelect;
export type Message = typeof messages.$inferSelect;
export type Attachment = typeof attachments.$inferSelect;
export type Reaction = typeof reactions.$inferSelect;
export type Pin = typeof pins.$inferSelect;
export type Invite = typeof invites.$inferSelect;
export type NotificationPref = typeof notificationPrefs.$inferSelect;
export type Activity = typeof activity.$inferSelect;
export type WorkspaceRole = (typeof workspaceRoleEnum.enumValues)[number];
export type ChannelKind = (typeof channelKindEnum.enumValues)[number];
