/**
 * Production entry point.
 *
 *  - `export const app` — the fully wired Hono app (tests/inspection).
 *  - `export default app.fetch` — a standard (request) => Response handler,
 *    exactly what Vercel's Bun runtime expects (see vercel.json).
 *  - `startServer()` — local HTTP server used by `bun src/index.ts` / dev.
 */
import { createApp } from "./app";
import { loadConfig } from "./config";

export const config = loadConfig();
export const app = createApp({ config });

export default app.fetch;

/** Boot the local server; `port: 0` picks a free port (used by tests). */
export function startServer(port: number = config.port): ReturnType<typeof Bun.serve> {
  const server = Bun.serve({
    port,
    hostname: "0.0.0.0",
    fetch: app.fetch,
  });
  console.log(`[stilora-api] listening on http://localhost:${server.port} (${config.nodeEnv})`);
  return server;
}

if (import.meta.main) {
  startServer();
}
