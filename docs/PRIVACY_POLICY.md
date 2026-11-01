# Privacy Policy — Hush

**Last updated:** 2026-11-02

Hush is an open-source communication app. This policy explains what we
collect, what we don't, and your choices. It is written to satisfy Google
OAuth verification, Android App Links verification, and app-store
requirements — while staying honest about a small, open project.

## What we collect

| Data | Why | Where |
|---|---|---|
| Email address | Sign you in (magic link / Google) | Auth database (Neon Postgres) |
| Display name, workspace membership | Show you in workspaces and messages | App database |
| Messages, files you send | The core service | App database + object storage |
| Mic/camera audio & video | Only while you are in a voice/video room; transmitted live to other participants | Peer-to-peer / LiveKit media servers — **not stored** |
| Crash reports (optional) | Diagnose bugs — only if enabled via build-time `SENTRY_DSN` | Sentry |

## What we do NOT collect

- **No end-to-end messaging surveillance:** we do not sell, analyze, or
  advertise against your content. Messages are processed to deliver them —
  nothing more.
- **No voice recordings.** Voice/video streams are relayed, never recorded
  or stored by Hush.
- **No location, contacts, or advertising identifiers.**
- **No tracking SDKs / analytics.** Crash reporting is opt-in per build.

## Encryption

Hush encrypts data **in transit** (TLS) and **at rest** (database and
storage encryption provided by our infrastructure). We do not claim
end-to-end encryption for group channels in this version.

## Sharing

We use infrastructure processors to run the service (hosting, database,
auth, realtime, voice relay, crash reporting). They process data only on
our instructions to provide the service. We do not sell data to anyone.

## Retention & deletion

Account data is kept while your account exists. Deleting your account
removes your profile and messages (soft-deleted rows are purged
periodically). Backups age out on a rolling schedule.

## Children

Hush is not directed at children under 13 (or the minimum age in your
region).

## Changes

Material changes will be announced in the app or on the project repository.

## Contact

Open an issue at the project repository or email the maintainers listed
there.
