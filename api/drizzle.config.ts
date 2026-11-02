import { defineConfig } from "drizzle-kit";

// drizzle-kit only needs a URL for `push`/`pull`; `generate` is purely local.
// Falls back to the docker-compose defaults from docker-compose.yml so
// `bun run db:generate` works out of the box for contributors.
export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url:
      process.env.DATABASE_URL ??
      "postgres://stilora:stilora@localhost:5432/stilora",
  },
  strict: true,
  verbose: true,
});
