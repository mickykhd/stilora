# Stilora — Release QA Checklist (the release gate)

Nothing tags without every box checked. Automated parts run in CI; the
manual parts are for a human on real hardware.

## 1. Automated (CI must be green on the release commit)

- [ ] `flutter analyze` → *No issues found!*
- [ ] `flutter test` → 80/80 (unit + widget + a11y + 28 goldens)
- [ ] `cd api && bun run typecheck` → 0 errors
- [ ] `bun test --coverage` → ≥90% total, ≥95% `src/auth/middleware.ts`
- [ ] Gitleaks secret scan → clean
- [ ] `bun audit` + `flutter pub audit` → no high/critical
- [ ] Linux release build → `flutter build linux --release` succeeds
- [ ] Android release build → `flutter build apk --release` succeeds

## 2. Manual E2E flows (Maestro scripts or hand-run)

- [ ] Sign in with email + password → workspace opens
- [ ] Wrong password → inline error, no session
- [ ] Create account (email + password + workspace name) → lands signed in
- [ ] Open channel → send message → appears (and in a 2nd client instantly)
- [ ] Edit / delete message (author only; non-author blocked)
- [ ] Thread: open from "N replies" → reply → count updates
- [ ] Reactions: add/remove, count correct, "mine" state distinct
- [ ] Pin / unpin → header pin count updates
- [ ] ⌘K palette: arrow navigation, Enter opens, ESC closes; full search
      screen returns grouped results
- [ ] DM: open Sarah → send → preview + timestamp update in list
- [ ] Channel create sheet → channel appears in sidebar
- [ ] Members sheet → tap member → profile → Message button
- [ ] Notifications: mark-all-read clears dots
- [ ] Settings: every section opens; Appearance switches light/dark live
- [ ] Offline: kill network → banner shows, cached history readable,
      retry works on reconnect

## 3. Voice QA (real devices — this cannot be automated)

- [ ] Join room from capsule and from Voice tab; states: connecting → connected
- [ ] Mic **permission denied** path: explainer card → Open settings works
- [ ] Mute/unmute from capsule, stage, and controls bar stay in sync
- [ ] Camera on/off; screen share toggle
- [ ] **Android lock screen / background**: audio keeps playing, notification
      media controls appear
- [ ] Speaker/earpiece routing on phone; Bluetooth headset test
- [ ] Reconnect after airplane-mode toggle (≤ few seconds, capsule shows
      reconnecting)
- [ ] Call behind restrictive NAT (mobile data) → TURN relay path works
- [ ] Leave room → capsule disappears everywhere for all participants

## 4. Platform matrix

- [ ] Android 10 / 13 / 15 physical devices
- [ ] Linux (Ubuntu 24.04+): build, run, GTK window, audio via PulseAudio
- [ ] Windows 11 (on a Windows machine): build with VS2022, run, audio
- [ ] 200% system text scale — no clipping (spot-check sign-in, settings)
- [ ] TalkBack (Android) spot-check: sign-in, chat, voice controls announce

## 5. Release mechanics

- [ ] Version bumped (`pubspec.yaml` + about dialog string)
- [ ] Privacy policy + Terms links live
- [ ] APK built with release keystore; `--dart-define=SENTRY_DSN=…` only if
      crash reporting is desired for this build
- [ ] Release notes written (calm tone, no hype)
- [ ] Tag pushed → CI runs post-deploy smoke test (health, sign-in, send,
      search)
