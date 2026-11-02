/**
 * Migration runner.
 *
 * - `up`    applies every drizzle/meta/_journal.json entry that has not been
 *            applied yet (tracked in `stilora_migrations`).
 * - `down`  rolls back applied entries in reverse order using the hand-written
 *            `drizzle/<tag>.down.sql` files (drizzle-kit has no down
 *            migrations of its own — see README).
 *
 * Both directions are idempotent, which is what migrations.test.ts asserts.
 *
 * CLI: `bun src/db/migrate.ts up|down`  (wired to `bun run db:migrate` /
 * `bun run db:rollback` in package.json).
 */
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { sql } from "drizzle-orm";
import { resultRows, type DB } from "./client";

const DEFAULT_DIR = join(import.meta.dir, "..", "..", "drizzle");

interface JournalEntry {
  idx: number;
  tag: string;
  breakpoints?: boolean;
}

interface Journal {
  entries: JournalEntry[];
}

export interface MigrationFile {
  idx: number;
  tag: string;
  up: string;
}

const TRACKING_DDL = sql`
  CREATE TABLE IF NOT EXISTS stilora_migrations (
    tag TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )
`;

function splitStatements(batch: string): string[] {
  return batch
    .split("--> statement-breakpoint")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export async function loadMigrations(dir: string = DEFAULT_DIR): Promise<MigrationFile[]> {
  const journal = JSON.parse(await readFile(join(dir, "meta", "_journal.json"), "utf8")) as Journal;
  const files: MigrationFile[] = [];
  for (const entry of [...journal.entries].sort((a, b) => a.idx - b.idx)) {
    const up = await readFile(join(dir, `${entry.tag}.sql`), "utf8");
    files.push({ idx: entry.idx, tag: entry.tag, up });
  }
  return files;
}

async function appliedTags(db: DB): Promise<Set<string>> {
  await db.execute(TRACKING_DDL);
  const rows = resultRows<{ tag: string }>(await db.execute(sql`SELECT tag FROM stilora_migrations`));
  return new Set(rows.map((r) => r.tag));
}

/** Apply all pending migrations. Returns the tags that were applied. */
export async function applyMigrations(db: DB, dir: string = DEFAULT_DIR): Promise<string[]> {
  const files = await loadMigrations(dir);
  const applied = await appliedTags(db);
  const ran: string[] = [];
  for (const file of files) {
    if (applied.has(file.tag)) continue;
    const statements = splitStatements(file.up);
    await db.transaction(async (tx) => {
      for (const statement of statements) {
        await tx.execute(sql.raw(statement));
      }
      await tx.execute(sql`INSERT INTO stilora_migrations (tag) VALUES (${file.tag})`);
    });
    ran.push(file.tag);
  }
  return ran;
}

/**
 * Roll back already-applied migrations newest-first using `<tag>.down.sql`.
 * Throws when a down file is missing so we never half-rollback.
 */
export async function rollbackMigrations(db: DB, dir: string = DEFAULT_DIR): Promise<string[]> {
  const files = await loadMigrations(dir);
  const applied = await appliedTags(db);
  const reverted: string[] = [];
  for (const file of [...files].reverse()) {
    if (!applied.has(file.tag)) continue;
    let down: string;
    try {
      down = await readFile(join(dir, `${file.tag}.down.sql`), "utf8");
    } catch {
      throw new Error(
        `Missing down migration for "${file.tag}" (expected ${join(dir, `${file.tag}.down.sql`)})`,
      );
    }
    const statements = splitStatements(down);
    await db.transaction(async (tx) => {
      for (const statement of statements) {
        await tx.execute(sql.raw(statement));
      }
      await tx.execute(sql`DELETE FROM stilora_migrations WHERE tag = ${file.tag}`);
    });
    reverted.push(file.tag);
  }
  return reverted;
}

/** CLI entry point (only runs when executed directly: `bun src/db/migrate.ts up`). */
async function main(): Promise<void> {
  const cmd = process.argv[2] ?? "up";
  const { loadConfig } = await import("../config");
  const { createDb } = await import("./client");
  const config = loadConfig();
  const { db, close } = createDb(config.databaseUrl);
  try {
    if (cmd === "up") {
      const ran = await applyMigrations(db);
      console.log(ran.length ? `Applied: ${ran.join(", ")}` : "Already up to date.");
    } else if (cmd === "down") {
      const reverted = await rollbackMigrations(db);
      console.log(reverted.length ? `Rolled back: ${reverted.join(", ")}` : "Nothing to roll back.");
    } else {
      console.error(`Unknown command "${cmd}". Usage: migrate.ts [up|down]`);
      process.exitCode = 1;
    }
  } finally {
    await close();
  }
}

if (import.meta.main) {
  await main();
}
