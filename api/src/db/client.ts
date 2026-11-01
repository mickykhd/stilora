/**
 * Drizzle client factory.
 *
 * postgres-js speaks plain wire-protocol Postgres, so the SAME code path works
 * against local docker-compose Postgres in dev and Neon in prod (Neon accepts
 * standard PG connections; append ?sslmode=require to DATABASE_URL).
 *
 * Tests inject a PGlite-backed drizzle instance instead (see tests/helpers.ts)
 * so the suite runs with zero external services.
 */
import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

/**
 * The database handle used across the app.
 *
 * Note: tests build an equivalent drizzle instance on top of PGlite
 * (`drizzle-orm/pglite`) and cast it to DB. Both drivers implement the same
 * pg-core query builder API; only the transport differs.
 */
export type DB = PostgresJsDatabase<typeof schema>;

export interface DbHandle {
  db: DB;
  close: () => Promise<void>;
}

export function createDb(databaseUrl: string): DbHandle {
  const client = postgres(databaseUrl, {
    max: 10,
    idle_timeout: 20,
    connect_timeout: 10,
  });
  const db = drizzle(client, { schema });
  return {
    db,
    close: async () => {
      await client.end({ timeout: 5 });
    },
  };
}

/** Postgres unique_violation (23505) — mapped to HTTP 409 by routes.
 * Drizzle wraps driver errors (err.cause), so walk the chain. */
export function isUniqueViolation(err: unknown): boolean {
  let current: unknown = err;
  for (let depth = 0; depth < 5 && current !== null && current !== undefined; depth++) {
    if (typeof current === "object" && (current as { code?: unknown }).code === "23505") {
      return true;
    }
    current = (current as { cause?: unknown }).cause;
  }
  return false;
}

/**
 * Normalize `db.execute()` results across drivers:
 *  - postgres-js returns an array-like RowList
 *  - pglite returns { rows, fields, affectedRows }
 */
export function resultRows<T>(result: unknown): T[] {
  if (Array.isArray(result)) return result as T[];
  if (result !== null && typeof result === "object" && "rows" in result) {
    return (result as { rows: T[] }).rows;
  }
  return [];
}
