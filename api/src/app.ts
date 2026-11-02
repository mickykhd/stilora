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
// Pre-bundled app (bun build via vercel.json#buildCommand) — static so the
// function evaluates exactly one self-contained module at load.
import handler from "./app.bundle.mjs";

// The `hono` value import exists solely so Vercel's framework detector
// recognizes this file as the hono entrypoint; the type reference marks
// it as intentionally used for the strict no-unused-locals check.
export type VercelHonoEntryMarker = typeof Hono;

const entry = (request: Request, server?: unknown) => handler(request, server);

// Vercel's launcher switches to Web-fetch mode ONLY when the default
// export carries `.fetch`; a bare function is invoked as Node (req,res)
// (returns ignored → hung invocations). See the launcher warning in the
// docs: "export a fetch function".
export default Object.assign(entry, { fetch: entry });

