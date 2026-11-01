/**
 * Migrations: up → assert tables + indexes (incl. the GIN full-text index and
 * partial indexes) → down → assert everything dropped → up again (idempotent)
 * → repeated up is a no-op, repeated down is a no-op.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { sql } from "drizzle-orm";
import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { applyMigrations, loadMigrations, rollbackMigrations } from "../src/db/migrate";
import { resultRows, type DB } from "../src/db/client";
import * as schema from "../src/db/schema";

const EXPECTED_TABLES = [
  "users",
  "sessions",
  "accounts",
  "verifications",
  "workspaces",
  "workspace_members",
  "channels",
  "channel_members",
  "messages",
  "attachments",
  "reactions",
  "pins",
  "invites",
  "notification_prefs",
  "activity",
];

let pglite: PGlite;
let db: DB;

beforeAll(async () => {
  pglite = new PGlite();
  db = drizzle(pglite, { schema }) as unknown as DB;
});
afterAll(async () => {
  await pglite?.close();
});

async function tableNames(): Promise<string[]> {
  const rows = resultRows<{ table_name: string }>(
    await db.execute(sql`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`),
  );
  return rows.map((r) => r.table_name);
}

async function indexNames(): Promise<Array<{ indexname: string; indexdef: string }>> {
  return resultRows<{ indexname: string; indexdef: string }>(
    await db.execute(sql`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'`),
  );
}

async function typeNames(): Promise<string[]> {
  const rows = resultRows<{ typname: string }>(
    await db.execute(sql`
      SELECT typname FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public' AND t.typtype = 'e'`),
  );
  return rows.map((r) => r.typname);
}

describe("migrations", () => {
  test("up creates every table, enum and index (incl. GIN full-text)", async () => {
    const applied = await applyMigrations(db);
    expect(applied.length).toBeGreaterThan(0);

    const tables = await tableNames();
    for (const expected of EXPECTED_TABLES) {
      expect(tables).toContain(expected);
    }

    const enums = await typeNames();
    expect(enums).toContain("workspace_role");
    expect(enums).toContain("channel_kind");

    const indexes = await indexNames();
    const names = indexes.map((i) => i.indexname);
    expect(names).toContain("messages_channel_created_at_idx"); // (channel_id, created_at DESC)
    expect(names).toContain("messages_thread_parent_idx"); // partial: thread_parent_id IS NOT NULL
    expect(names).toContain("messages_content_fts_idx"); // GIN to_tsvector('english', content)
    expect(names).toContain("activity_user_unread_idx"); // partial: read_at IS NULL
    expect(names).toContain("workspace_members_workspace_user_unique");
    expect(names).toContain("reactions_message_user_emoji_unique");
    expect(names).toContain("pins_channel_message_unique");
    expect(names).toContain("channels_workspace_name_unique");

    const fts = indexes.find((i) => i.indexname === "messages_content_fts_idx");
    expect(fts?.indexdef).toContain("to_tsvector('english'"); // pg renders 'english'::regconfig
    expect(fts?.indexdef).toContain("content)");
    expect(fts?.indexdef.toLowerCase()).toContain("using gin");

    const partialThread = indexes.find((i) => i.indexname === "messages_thread_parent_idx");
    expect(partialThread?.indexdef).toContain("thread_parent_id IS NOT NULL");
    expect(partialThread?.indexdef).toContain("WHERE");
  });

  test("full-text search actually works right after migrate", async () => {
    // schema-level smoke: insert through drizzle and query with tsquery
    const { users, workspaces, workspaceMembers, channels, messages } = schema;
    const [user] = await db
      .insert(users)
      .values({ id: "mig-user", name: "Mig", email: "mig@example.com" })
      .returning();
    const [ws] = await db
      .insert(workspaces)
      .values({ name: "Mig WS", slug: "mig-ws", inviteCode: "MIGCODE1" })
      .returning();
    await db.insert(workspaceMembers).values({ workspaceId: ws!.id, userId: user!.id, role: "owner" });
    const [ch] = await db
      .insert(channels)
      .values({ workspaceId: ws!.id, name: "mig", kind: "public", createdBy: user!.id })
      .returning();
    await db.insert(messages).values({ channelId: ch!.id, authorId: user!.id, content: "walruses appear" });

    const hits = resultRows<{ id: string }>(
      await db.execute(sql`
        SELECT id FROM messages
        WHERE deleted_at IS NULL
          AND to_tsvector('english', content) @@ websearch_to_tsquery('english', 'walruses')`),
    );
    expect(hits.length).toBe(1);
  });

  test("second up is a no-op (idempotent)", async () => {
    const again = await applyMigrations(db);
    expect(again).toHaveLength(0);
  });

  test("down drops every table + enum, and is itself idempotent", async () => {
    const reverted = await rollbackMigrations(db);
    expect(reverted.length).toBeGreaterThan(0);

    const tables = await tableNames();
    for (const expected of EXPECTED_TABLES) {
      expect(tables).not.toContain(expected);
    }
    const enums = await typeNames();
    expect(enums).not.toContain("workspace_role");
    expect(enums).not.toContain("channel_kind");

    const nothing = await rollbackMigrations(db);
    expect(nothing).toHaveLength(0);
  });

  test("up → down → up round-trip ends in the same schema", async () => {
    const applied = await applyMigrations(db);
    expect(applied.length).toBeGreaterThan(0);

    const tables = await tableNames();
    for (const expected of EXPECTED_TABLES) {
      expect(tables).toContain(expected);
    }
    const indexes = await indexNames();
    expect(indexes.map((i) => i.indexname)).toContain("messages_content_fts_idx");
  });

  test("every journal entry has a hand-written down migration", async () => {
    const files = await loadMigrations();
    expect(files.length).toBeGreaterThan(0);
    for (const file of files) {
      // loadMigrations only reads .sql ups; verify the down file exists via rollback loader
      expect(file.tag).toMatch(/^\d{4}_/);
      expect(file.up.length).toBeGreaterThan(0);
    }
    // rollback after a fresh apply proves down files exist for all entries
    const reverted = await rollbackMigrations(db);
    expect(reverted.length).toBe(files.length);
  });

  test("rollback refuses to half-rollback when a down file is missing", async () => {
    const { mkdir, writeFile, rm } = await import("node:fs/promises");
    const { tmpdir } = await import("node:os");
    const { join } = await import("node:path");

    const dir = join(tmpdir(), `hush-mig-${Date.now()}`);
    await mkdir(join(dir, "meta"), { recursive: true });
    await writeFile(
      join(dir, "meta", "_journal.json"),
      JSON.stringify({ version: "7", dialect: "postgresql", entries: [{ idx: 0, version: "7", when: 1, tag: "9999_orphan", breakpoints: true }] }),
    );
    await writeFile(join(dir, "9999_orphan.sql"), "SELECT 1;");
    // note: 9999_orphan.down.sql deliberately missing

    await db.execute(sql`INSERT INTO hush_migrations (tag) VALUES ('9999_orphan')`);
    try {
      let message = "";
      try {
        await rollbackMigrations(db, dir);
      } catch (err) {
        message = err instanceof Error ? err.message : String(err);
      }
      expect(message).toContain("Missing down migration");
      expect(message).toContain("9999_orphan");
    } finally {
      await db.execute(sql`DELETE FROM hush_migrations WHERE tag = '9999_orphan'`);
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe("db client helpers", () => {
  test("createDb is lazy — construct + close without ever dialing", async () => {
    const { createDb } = await import("../src/db/client");
    const handle = createDb("postgres://user:pass@127.0.0.1:59999/never-reached");
    expect(handle.db).toBeDefined();
    await handle.close(); // no connection was opened; resolves immediately
  });

  test("resultRows normalizes both driver shapes", async () => {
    const { resultRows } = await import("../src/db/client");
    expect(resultRows<{ a: number }>([{ a: 1 }])).toEqual([{ a: 1 }]);
    expect(resultRows<{ a: number }>({ rows: [{ a: 2 }] })).toEqual([{ a: 2 }]);
    expect(resultRows({ fields: [] })).toEqual([]);
    expect(resultRows(null)).toEqual([]);
  });

  test("isUniqueViolation detects 23505 directly and through cause chains", async () => {
    const { isUniqueViolation } = await import("../src/db/client");
    expect(isUniqueViolation({ code: "23505" })).toBe(true);
    expect(isUniqueViolation(new Error("wrapped", { cause: { code: "23505" } }))).toBe(true);
    expect(
      isUniqueViolation({ cause: { cause: { code: "23505" } } }),
    ).toBe(true);
    expect(isUniqueViolation({ code: "23503" })).toBe(false);
    expect(isUniqueViolation(null)).toBe(false);
    expect(isUniqueViolation("23505")).toBe(false);
  });
});
