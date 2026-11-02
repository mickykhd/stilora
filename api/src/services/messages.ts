/**
 * Shared message logic: creation, cursor pagination and response enrichment
 * (attachments, grouped reactions, reply counts, pinned flag) — used by
 * channel, thread and DM routes.
 */
import { and, asc, desc, eq, inArray, isNull, sql } from "drizzle-orm";
import type { DB } from "../db/client";
import { attachments, messages, pins, reactions, type Message } from "../db/schema";
import type { Cursor } from "../http";

export interface AttachmentView {
  id: string;
  storageKey: string;
  mimeType: string | null;
  sizeBytes: number;
  originalName: string | null;
}

export interface ReactionSummary {
  emoji: string;
  count: number;
  userIds: string[];
}

export interface MessageView {
  id: string;
  channelId: string;
  authorId: string | null;
  threadParentId: string | null;
  content: string;
  createdAt: string;
  updatedAt: string;
  editedAt: string | null;
  attachments: AttachmentView[];
  reactions: ReactionSummary[];
  replyCount: number;
  pinned: boolean;
}

export interface PageResult<T> {
  rows: T[];
  hasMore: boolean;
}

/** Build MessageView rows with batched lookups (N+1-free for one page). */
export async function enrichMessages(db: DB, rows: Message[]): Promise<MessageView[]> {
  if (rows.length === 0) return [];
  const ids = rows.map((r) => r.id);

  const [attRows, reactionRows, replyCountRows, pinnedRows] = await Promise.all([
    db
      .select()
      .from(attachments)
      .where(inArray(attachments.messageId, ids)),
    db
      .select({
        messageId: reactions.messageId,
        userId: reactions.userId,
        emoji: reactions.emoji,
      })
      .from(reactions)
      .where(inArray(reactions.messageId, ids)),
    db
      .select({
        parentId: messages.threadParentId,
        count: sql<string>`count(*)::int`,
      })
      .from(messages)
      .where(and(inArray(messages.threadParentId, ids), isNull(messages.deletedAt)))
      .groupBy(messages.threadParentId),
    db.select({ messageId: pins.messageId }).from(pins).where(inArray(pins.messageId, ids)),
  ]);

  const attachmentsByMessage = new Map<string, AttachmentView[]>();
  for (const a of attRows) {
    const view: AttachmentView = {
      id: a.id,
      storageKey: a.storageKey,
      mimeType: a.mimeType,
      sizeBytes: a.sizeBytes,
      originalName: a.originalName,
    };
    const list = attachmentsByMessage.get(a.messageId) ?? [];
    list.push(view);
    attachmentsByMessage.set(a.messageId, list);
  }

  const reactionMap = new Map<string, Map<string, ReactionSummary>>();
  for (const r of reactionRows) {
    const perMessage = reactionMap.get(r.messageId) ?? new Map<string, ReactionSummary>();
    const summary = perMessage.get(r.emoji) ?? { emoji: r.emoji, count: 0, userIds: [] };
    summary.count += 1;
    summary.userIds.push(r.userId);
    perMessage.set(r.emoji, summary);
    reactionMap.set(r.messageId, perMessage);
  }

  const replyCounts = new Map<string, number>();
  for (const r of replyCountRows) {
    if (r.parentId) replyCounts.set(r.parentId, Number(r.count));
  }

  const pinnedSet = new Set(pinnedRows.map((p) => p.messageId));

  return rows.map((m) => ({
    id: m.id,
    channelId: m.channelId,
    authorId: m.authorId,
    threadParentId: m.threadParentId,
    content: m.content,
    createdAt: m.createdAt.toISOString(),
    updatedAt: m.updatedAt.toISOString(),
    editedAt: m.editedAt ? m.editedAt.toISOString() : null,
    attachments: attachmentsByMessage.get(m.id) ?? [],
    reactions: [...(reactionMap.get(m.id)?.values() ?? [])].sort((a, b) =>
      a.emoji.localeCompare(b.emoji),
    ),
    replyCount: replyCounts.get(m.id) ?? 0,
    pinned: pinnedSet.has(m.id),
  }));
}

export interface CreateMessageInput {
  channelId: string;
  authorId: string;
  content: string;
  threadParentId?: string | null;
  attachments?: Array<{
    storageKey: string;
    mimeType?: string | undefined;
    sizeBytes: number;
    originalName?: string | undefined;
  }>;
}

/** Insert a message (+ attachments) atomically. authorId always comes from
 * the session — callers must never forward a client-supplied author. */
export async function createMessage(
  db: DB,
  input: CreateMessageInput,
): Promise<{ row: Message; attachments: AttachmentView[] }> {
  return await db.transaction(async (tx) => {
    const inserted = await tx
      .insert(messages)
      .values({
        channelId: input.channelId,
        authorId: input.authorId,
        content: input.content,
        threadParentId: input.threadParentId ?? null,
      })
      .returning();
    const row = inserted[0];
    if (!row) throw new Error("message insert returned no row");

    let attachmentRows: AttachmentView[] = [];
    if (input.attachments && input.attachments.length > 0) {
      const rows = await tx
        .insert(attachments)
        .values(
          input.attachments.map((a) => ({
            messageId: row.id,
            storageKey: a.storageKey,
            mimeType: a.mimeType ?? null,
            sizeBytes: a.sizeBytes,
            originalName: a.originalName ?? null,
          })),
        )
        .returning();
      attachmentRows = rows.map((a) => ({
        id: a.id,
        storageKey: a.storageKey,
        mimeType: a.mimeType,
        sizeBytes: a.sizeBytes,
        originalName: a.originalName,
      }));
    }
    return { row, attachments: attachmentRows };
  });
}

/**
 * Channel feed: root (non-reply), non-deleted messages, newest first,
 * keyset-paginated on (created_at, id).
 */
export async function listChannelRootMessages(
  db: DB,
  options: { channelId: string; cursor: Cursor | null; limit: number },
): Promise<PageResult<Message>> {
  const conditions = [
    eq(messages.channelId, options.channelId),
    isNull(messages.deletedAt),
    isNull(messages.threadParentId),
  ];
  if (options.cursor) {
    conditions.push(
      sql`(${messages.createdAt}, ${messages.id}) < (${new Date(options.cursor.t)}, ${options.cursor.i})`,
    );
  }
  const rows = await db
    .select()
    .from(messages)
    .where(and(...conditions))
    .orderBy(desc(messages.createdAt), desc(messages.id))
    .limit(options.limit + 1);

  const hasMore = rows.length > options.limit;
  return { rows: hasMore ? rows.slice(0, options.limit) : rows, hasMore };
}

/** Thread replies: chronological (oldest first), keyset-paginated ascending. */
export async function listThreadReplies(
  db: DB,
  options: { rootId: string; cursor: Cursor | null; limit: number },
): Promise<PageResult<Message>> {
  const conditions = [
    eq(messages.threadParentId, options.rootId),
    isNull(messages.deletedAt),
  ];
  if (options.cursor) {
    conditions.push(
      sql`(${messages.createdAt}, ${messages.id}) > (${new Date(options.cursor.t)}, ${options.cursor.i})`,
    );
  }
  const rows = await db
    .select()
    .from(messages)
    .where(and(...conditions))
    .orderBy(asc(messages.createdAt), asc(messages.id))
    .limit(options.limit + 1);

  const hasMore = rows.length > options.limit;
  return { rows: hasMore ? rows.slice(0, options.limit) : rows, hasMore };
}

export async function getMessageById(db: DB, id: string): Promise<Message | null> {
  const rows = await db.select().from(messages).where(eq(messages.id, id)).limit(1);
  return rows[0] ?? null;
}
