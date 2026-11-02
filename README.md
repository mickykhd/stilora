# Stilora

> A calm, focused communication workspace. Attention is a finite resource —
> Stilora treats it that way.

Stilora is a cross-platform communication app (think quiet Slack/Discord) with
channels, threads, DMs, reactions, pins, ⌘K search, and low-noise voice rooms.
One Flutter codebase ships to **Android, Linux, and Windows**.

## Repository layout

| Path | What it is |
|---|---|
| `stilora/` | The Flutter app (Android + Linux + Windows) |
| `api/` | Backend — Bun + Hono + Drizzle on Postgres (deploys to Vercel) |
| `stitch_cross_platform_minimalist_communication_app/` | Original design mockups (HTML) + [`aura/DESIGN.md`](stitch_cross_platform_minimalist_communication_app/aura/DESIGN.md) design system |
| `docs/` | Privacy policy, terms, QA checklist |
| `.github/workflows/` | CI — every gate is blocking |

## The stack — $0, all open source

| Layer | Choice | Cost |
|---|---|---|
| App | Flutter (BSD) — one codebase, 3 platforms | $0 |
| Design system | [`aura/DESIGN.md`](aura/DESIGN.md) — single source of truth | $0 |
| API | **Bun 1.4 + Hono** on Vercel Functions | $0 (Hobby) |
| Database | **Neon Postgres** + Drizzle ORM | $0 |
| Auth | **Better Auth** — email + password (our own DB, no third-party OAuth) | $0 |
| Realtime | **Ably** free tier (typing, presence, voice state) | $0 |
| Voice/video | **LiveKit Cloud** free tier + Open Relay TURN | $0 |
| Storage | S3-compatible signed uploads (R2/MinIO) | $0 |
| Monitoring | Sentry free tier (opt-in via `SENTRY_DSN`) | $0 |
| CI | GitHub Actions (public repo) | $0 |

> Vercel's Hobby plan is for **non-commercial** projects. If Stilora ever
> commercializes, budget Vercel Pro + paid tiers of the services above.

## Quickstart

### App

```bash
cd stilora
flutter pub get
flutter run                 # picks a connected device / Linux desktop
flutter test                # unit + widget + golden suites (80 tests)
flutter build linux --release
```

Linux desktop build deps (Ubuntu):

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev liblzma-dev libpulse-dev
```

Windows builds require a Windows machine with Visual Studio 2022
("Desktop development with C++"). Android APKs build on any platform.

### Backend

```bash
cd api
bun install
cp .env.example .env        # fill in values (see table in api/README.md)
docker compose up -d        # local Postgres 16 (or use a Neon branch)
bun run db:generate && bun run db:push
bun run dev
bun test --coverage         # 332 tests, ≥90% coverage gate
```

Deploy: push to GitHub → import in Vercel with `"bunVersion": "1.x"` in
`vercel.json` (already present).

## Design system

All visual tokens (colors light+dark, Geist typography, spacing, radii,
motion, focus, presence, breakpoints) live in
[`aura/DESIGN.md`](stitch_cross_platform_minimalist_communication_app/aura/DESIGN.md)
and are mirrored 1:1 in `stilora/lib/src/theme/tokens.dart`. Golden tests fail
CI on any pixel drift.

## Security model

- The Flutter app **never** touches the database — every query flows through
  the Bun API.
- `api/src/auth/middleware.ts` is the security boundary (100% test coverage).
- The 4-way auth matrix is enforced on **every** endpoint:
  member → 2xx · anonymous → 401 · non-member → 403 (no existence leaks) ·
  malformed/abusive → 4xx, then 429 rate-limit.
- Author identity always comes from the session — spoofed `author_id` is
  ignored and verified against the DB in tests.

## Testing policy (full strict — all gates block merges)

- **Flutter:** 80 tests — unit (tokens/models/repos), widget (components,
  a11y semantics, 44px targets, 200% text scale, reduced motion),
  **28 golden screenshots** (3 breakpoints × light/dark).
- **API:** 332 tests — auth matrix, IDOR, migrations up/down, FTS fixtures,
  rate limits, LiveKit tokens. Coverage ≥90% overall, ≥95% middleware.
- **Security:** Gitleaks secret scan + `bun audit` + `flutter pub audit`.
- **Release:** see [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md) — nothing
  tags without it.

## License

[MIT](LICENSE). Geist typeface is SIL OFL (bundled in `stilora/assets/fonts`).
