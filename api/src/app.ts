/**
 * Vercel framework-preset entry (hono slug): the preset compiles THIS
 * file into src/app.js — keep its import graph tiny so Vercel's file
 * tracer can't prune anything real:
 *   - "hono"           → traced complete (verified in prior builds)
 *   - app.bundle.mjs   → ONE self-contained file from buildCommand
 *                        (bun build inlines the entire dependency tree,
 *                        including better-auth, into it)
 *
 * The actual application lives in ./create-app (factory, used by tests
 * and by src/main.ts when producing the bundle).
 */
import { Hono } from "hono";

// The `hono` value import exists solely so Vercel's framework detector
// recognizes this file as the hono entrypoint; the type reference marks
// it as intentionally used for the strict no-unused-locals check.
export type VercelHonoEntryMarker = typeof Hono;

export default (request: Request, server?: unknown) =>
  import("./app.bundle.mjs").then((m) => m.default(request, server));

