/**
 * Production entry point: exports the app for tests/inspection and a standard
 * fetch handler for Vercel's Bun runtime (see vercel.json).
 *
 * NOTE: we never *invoke* the handler here — its default dependencies point at
 * DATABASE_URL, and only a real request would dial the database.
 */
import { describe, expect, test } from "bun:test";

describe("src/index.ts", () => {
  test("exports `app` and a default fetch handler (Vercel Bun runtime contract)", async () => {
    const mod = (await import("../src/index")) as {
      app: { fetch: (request: Request) => Response | Promise<Response> };
      default: (request: Request) => Response | Promise<Response>;
      config: { betterAuthUrl: string; nodeEnv: string };
    };

    expect(typeof mod.app.fetch).toBe("function");
    expect(typeof mod.default).toBe("function"); // export default app.fetch
    expect(mod.config.betterAuthUrl.length).toBeGreaterThan(0);
    // default handler and app.fetch are the same bound function
    expect(mod.default).toBe(mod.app.fetch);
  });

  test("config was resolved fail-fast from the environment (no throw = valid)", async () => {
    const mod = (await import("../src/index")) as { config: { databaseUrl: string } };
    expect(mod.config.databaseUrl).toBeTruthy();
  });

  test("startServer boots and stops cleanly (port 0 → ephemeral port)", async () => {
    const mod = (await import("../src/index")) as {
      startServer: (port: number) => { port: number; stop: (closeActiveConnections?: boolean) => void };
    };
    const server = mod.startServer(0);
    try {
      expect(server.port).toBeGreaterThan(0);
    } finally {
      server.stop(true);
    }
  });
});
