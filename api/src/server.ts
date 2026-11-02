/**
 * Vercel Bun framework preset entrypoint.
 *
 * Vercel's Bun runtime detects a `Bun.serve()` call made at module
 * startup and routes every incoming request through this single
 * function (https://vercel.com/docs/functions/runtimes/bun). The file
 * must be named `server.ts`/`src/server.ts` and `bun.lock` must exist.
 *
 * `port`/`hostname` only apply when running locally — Vercel ignores
 * them and injects the request via `fetch`.
 *
 * `./index` is imported for its config-validated app instance; its
 * own `import.meta.main` guard prevents a second server here.
 */
import { app, config } from "./index";

Bun.serve({
  port: config.port,
  hostname: "0.0.0.0",
  fetch: app.fetch,
});
