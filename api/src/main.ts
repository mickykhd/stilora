/**
 * Bundle entry: `bun build src/main.ts --target=bun --outfile=src/app.bundle.mjs`
 * (vercel.json#buildCommand). Produces ONE self-contained file — every
 * dependency inlined, zero runtime module resolution for Vercel's tracer
 * to prune. Not used directly at runtime; app.ts's default export lazy-
 * loads the built file.
 */
import { createApp } from "./create-app";
import { loadConfig } from "./config";

const app = createApp({ config: loadConfig() });
const handler = Object.assign(app.fetch, { fetch: app.fetch });
export default handler;
