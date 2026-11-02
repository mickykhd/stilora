# Stilora API

Backend for **Stilora** — an open-source, *calm* communication workspace.
Slack-like primitives (workspaces, channels, threads, DMs, reactions, pins,
voice rooms) behind a small, strict, fully self-hostable API.

Built with **Bun + Hono + Drizzle (Postgres) + Better Auth**, MIT licensed,
100% free/open tooling — no paid services required to run or develop it.

---

## Quickstart (local dev)

Requirements: [Bun ≥ 1.2](https://bun.sh) and Docker (for Postgres).

```bash
bun install                 # install dependencies
docker compose up -d        # start Postgres 16 (see docker-compose.yml)
cp .env.example .env        # configure environment (works out of the box locally)
bun run db:migrate          # apply SQL migrations (drizzle/)
bun run dev                 # API on http://localhost:3000
```

Smoke test it:

```bash
curl http://localhost:3000/api/health
# {"data":{"status":"ok","service":"stilora-api","database":"up",...}}

# Create an account (email + password — our own DB) and get a session:
curl -X POST http://localhost:3000/api/auth/sign-up/email \
  -H 'content-type: application/json' \
  -d '{"email":"you@example.com","password":"choose-a-good-password","name":"You"}'

# Sign back in:
curl -X POST http://localhost:3000/api/auth/sign-in/email \
  -H 'content-type: application/json' \
  -d '{"email":"you@example.com","password":"choose-a-good-password"}'
```

Run the test suite (zero external services — PGlite in-process Postgres,
in-memory event bus, fakes for LiveKit/storage):

```bash
bun test                  # 334 tests
bun run test:coverage     # + coverage report
bun run typecheck         # tsc --noEmit, strict mode
```

---

## Architecture

```
src/
  index.ts          production entry: exports `app` + default fetch handler (Vercel)
  app.ts            middleware pipeline + route wiring (createApp(deps) is injectable)
  config.ts         fail-fast env validation (zod)
  http.ts           {data} / {error,status} envelopes, cursor + body helpers
  context.ts        AppContext dependency bundle + Hono context types
  db/               drizzle client factory, schema, migration runner (up AND down)
  auth/             Better Auth config (email + password only — no OAuth,
                    no magic links) and THE security
                    boundary middlewares (requireAuth / requireWorkspaceMember /
                    requireChannelMember / requireMessageAccess / requireMessageAuthor)
  ratelimit/        in-process token buckets (auth / per-route / global, per IP)
  events/           EventBus interface + MemoryBus + Ably REST stub
  realtime/         typed event names & payloads (message.created, typing, ...)
  livekit/          access-token minting + voice room state (injectable)
  storage/          SigV4 presigned uploads (S3/R2) + local no-op mode
  services/         shared message pagination/enrichment, activity/deep-work
  routes/           one module per resource (see endpoint table below)
tests/              bun test suite incl. the 4-way auth matrix
drizzle/            generated SQL migrations + hand-written .down.sql files
```

### Security model (the 4-way matrix)

Every non-health endpoint is asserted against this matrix in
`tests/auth.matrix.test.ts`:

1. **valid session + workspace/channel member** → `2xx` with the right data
2. **anonymous** → `401 {"error":"unauthorized"}`
3. **valid session but NOT a member** → `403 {"error":"forbidden"}`
   — "doesn't exist" and "exists but isn't yours" are deliberately
   indistinguishable, so foreign workspace/channel/message ids can never be
   enumerated
4. **malformed ids / invalid payloads / bad tokens** → `4xx`;
   repeated violations → `429` with `Retry-After`

Identity (author ids, edit state) is **always** taken from the session —
client-supplied `author_id`-style fields are stripped by validation and
verified against the database in `tests/security.test.ts`.

Responses are always either `{"data": ...}` or `{"error": "...", "status": N}`
(with `status` mirroring the HTTP status). Every response carries an
`x-request-id` header that is also printed in error logs.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | ✅ | — | Postgres connection string (local docker-compose or Neon, `?sslmode=require`) |
| `BETTER_AUTH_SECRET` | ✅ | — | ≥ 32 chars; `openssl rand -base64 32` |
| `BETTER_AUTH_URL` | ✅ | — | Public base URL of the API, e.g. `https://api.example.com` (its origin is always CORS-allowed) |
| `ABLY_API_KEY` | — | — | Enables the Ably REST event bus; without it realtime is a no-op |
| `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | — | — | Voice rooms; all three or none (else `/api/voice/*` → 503) |
| `STORAGE_MODE` | — | `local` | `local` = no-op signer, `s3` = SigV4 presigned PUT URLs |
| `S3_ENDPOINT` / `S3_REGION` / `S3_BUCKET` / `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | — | — | S3-compatible storage (AWS S3, Cloudflare R2, MinIO). Bucket+keys required when `STORAGE_MODE=s3` |
| `MAX_UPLOAD_BYTES` | — | `26214400` | Per-file upload cap (25 MiB) |
| `ALLOWED_ORIGINS` | — | — | Comma-separated browser origins; **unknown origins get 403 and no CORS headers** |
| `RATE_LIMIT_AUTH_PER_MIN` | — | `30` | Auth routes (`/api/auth/*`) per IP |
| `RATE_LIMIT_ROUTE_PER_MIN` | — | `120` | Each other route, per IP |
| `RATE_LIMIT_GLOBAL_PER_MIN` | — | `600` | All traffic, per IP |
| `TRUST_PROXY` | — | `true` | Take client IP from first `x-forwarded-for` entry |
| `MAX_BODY_BYTES` | — | `1048576` | Request body cap → `413` |
| `SENTRY_DSN` | — | — | Reserved for future error tracking |
| `PORT` | — | `3000` | Local server port (ignored on Vercel) |
| `NODE_ENV` | — | `development` | `development` \| `production` \| `test` |

Missing/invalid **required** values fail fast at boot with a message listing
every problem at once.

---

## Endpoints

`Auth` column: 🔓 = public, 🛂 = requires session, 👑 = requires workspace
admin/owner role.

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/health` | 🔓 | Liveness + database status (exempt from rate limits) |
| * | `/api/auth/*` | 🔓 | Better Auth: sign-up/sign-in (email + password), get-session, sign-out |
| GET | `/api/workspaces` | 🛂 | List my workspaces (+ `inviteCode` for admin+) |
| POST | `/api/workspaces` | 🛂 | Create workspace (caller becomes owner) |
| GET | `/api/workspaces/:workspaceId` | 🛂 | Workspace detail |
| GET | `/api/workspaces/:workspaceId/members` | 🛂 | Members with roles |
| POST | `/api/workspaces/:workspaceId/invites` | 👑 | Create email invite (token + accept URL) |
| POST | `/api/workspaces/:workspaceId/join` | 🛂 | Join via workspace invite code |
| POST | `/api/invites/accept` | 🛂 | Accept an invite by token (atomic, single-use) |
| GET | `/api/workspaces/:workspaceId/channels` | 🛂 | List channels (private ones only if joined) |
| POST | `/api/workspaces/:workspaceId/channels` | 🛂 | Create public/private channel |
| GET | `/api/channels/:channelId` | 🛂 | Channel detail + my read state |
| PATCH | `/api/channels/:channelId` | 👑* | Rename / topic / archive (*or channel creator) |
| POST | `/api/channels/:channelId/members` | 👑* | Add a workspace member to the channel (*or creator) |
| POST | `/api/channels/:channelId/read` | 🛂 | Mark channel read up to a message |
| GET | `/api/channels/:channelId/messages` | 🛂 | Paginated feed (cursor, `limit≤50` default 50) |
| POST | `/api/channels/:channelId/messages` | 🛂 | Post message (+ attachments) |
| PATCH | `/api/messages/:messageId` | 🛂 (author) | Edit message (sets `editedAt`) |
| DELETE | `/api/messages/:messageId` | 🛂 (author/ADM) | Soft-delete message (content purged) |
| GET | `/api/messages/:messageId/replies` | 🛂 | Read thread (parent + replies, cursor) |
| POST | `/api/messages/:messageId/replies` | 🛂 | Reply (always attaches to thread root) |
| PUT | `/api/messages/:messageId/reactions` | 🛂 | Add reaction (idempotent) |
| DELETE | `/api/messages/:messageId/reactions` | 🛂 | Remove my reaction |
| GET | `/api/channels/:channelId/pins` | 🛂 | List pinned messages |
| POST | `/api/channels/:channelId/pins` | 🛂 | Pin a message (idempotent) |
| DELETE | `/api/channels/:channelId/pins` | 🛂 | Unpin a message |
| GET | `/api/dm/conversations` | 🛂 | My DM conversations (+ preview) |
| POST | `/api/workspaces/:workspaceId/dm/conversations` | 🛂 | Open/find a 1:1 conversation |
| GET | `/api/dm/conversations/:channelId/messages` | 🛂 | DM messages (cursor) |
| POST | `/api/dm/conversations/:channelId/messages` | 🛂 | Send DM (notifies recipients) |
| GET | `/api/search?q=&scope=` | 🛂 | Full-text search: `messages` / `channels` / `people`, scoped to my workspaces |
| POST | `/api/voice/token` | 🛂 | Mint LiveKit room token (identity = session user) |
| GET | `/api/voice/state` | 🛂 | Current voice room participants |
| POST | `/api/uploads/sign` | 🛂 | Signed PUT URL for an upload |
| GET | `/api/notifications` | 🛂 | Activity feed + unread count (cursor) |
| POST | `/api/notifications/read` | 🛂 | Mark notifications read |
| GET | `/api/notifications/prefs` | 🛂 | Notification preferences |
| PUT | `/api/notifications/prefs` | 🛂 | Deep-work / DND window (cross-midnight OK) |

Realtime events published through the `EventBus` (Ably channel names):
`message.created`, `message.updated`, `message.deleted`, `reaction.changed`,
`pin.changed`, `typing`, `presence`, `unread.bumped`, `voice.state`.

---

## Testing

```bash
bun test                # runs everything (no network, no Docker, no accounts)
bun run test:coverage   # with coverage report
```

* **Database:** [PGlite](https://electric-sql.com) (Postgres compiled to
  WASM) via `drizzle-orm/pglite`. `tests/helpers.ts` applies the *real*
  migration SQL on every app instance, so the suite also proves migrations on
  a clean Postgres. No Docker needed for tests.
* **Auth:** the real Better Auth email+password flow over HTTP — accounts
  are created and verified against our own Postgres, nothing external.
* **Realtime/Voice/Storage:** `MemoryBus`, injected LiveKit fakes, local
  no-op signer. The real `livekit-server-sdk` JWT signing and the SigV4
  presigner are pure computation and are unit-tested offline too.
* Key suites: `auth.matrix.test.ts` (the 4-way matrix across every endpoint),
  `security.test.ts` (IDOR both directions, 413 payloads, spoofed authors
  checked **in the database**, CORS deny), `migrations.test.ts`
  (up → assert indexes → down → up idempotent), plus one file per resource.

Current numbers: **334 tests, ~98% line coverage overall,
`src/auth/middleware.ts` at 100%.**

---

## Deploying to Vercel

1. Push this repo to GitHub and import it in Vercel.
2. Vercel detects Bun via `vercel.json` (`{"bunVersion": "1.x"}`); the
   default export is a plain `fetch(request)` handler — no framework preset
   needed.
3. Provision a Postgres database (e.g. Neon free tier) and set the required
   env vars from the table above in the project settings.
4. Run migrations from your machine/CI against the production database:

   ```bash
   DATABASE_URL="postgres://…neondb…" bun run db:migrate
   ```

5. Point `BETTER_AUTH_URL` at the deployed API origin. No third-party
   OAuth configuration exists — auth is email + password only.

Note: rate limiting is per-instance (in-process). Serverless instances each
keep their own buckets — fine as a abuse damper; put a shared limiter (e.g.
Upstash Redis behind the same `TokenBucketLimiter` interface) in front if you
need exact global limits.

---

## Self-hosting

```bash
git clone <repo> && cd api
bun install
docker compose up -d          # local Postgres 16
cp .env.example .env          # adjust secrets + ALLOWED_ORIGINS
bun run db:migrate
bun start                     # or: bun run dev (watch mode)
```

* Put it behind any reverse proxy (Caddy/nginx) that terminates TLS and sets
  `x-forwarded-for`; keep `TRUST_PROXY=true`.
* Backups = `pg_dump` of the single database; there is no other state
  (sessions included) besides your object storage bucket if you enable uploads.
* Everything runs offline except the integrations you explicitly configure
  (Ably, LiveKit, S3).

---

## License

[MIT](./LICENSE) — free for personal and commercial use.
