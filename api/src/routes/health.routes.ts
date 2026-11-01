/** GET /api/health — the only route that requires no authentication. */
import { sql } from "drizzle-orm";
import { Hono } from "hono";
import type { AppContext, AppEnv } from "../context";
import { ok } from "../http";

export function healthRoutes(ctx: AppContext): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.get("/api/health", async (c) => {
    let database: "up" | "down" = "down";
    try {
      const timeout = new Promise<never>((_, reject) => {
        const timer = setTimeout(() => reject(new Error("database check timed out")), 1_500);
        timer.unref();
      });
      await Promise.race([ctx.db.execute(sql`SELECT 1`), timeout]);
      database = "up";
    } catch {
      database = "down";
    }
    const up = database === "up";
    return ok(
      c,
      {
        status: up ? "ok" : "degraded",
        service: "hush-api",
        database,
        uptimeSeconds: Math.round(process.uptime()),
        time: new Date().toISOString(),
      },
      up ? 200 : 503,
    );
  });

  return app;
}
