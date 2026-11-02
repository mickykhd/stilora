# Contributing to Stilora

Thanks for helping keep communication calm. 🕊

## Ground rules

1. **DESIGN.md is law.** Visual changes start in `aura/DESIGN.md`; code
   follows tokens in `stilora/lib/src/theme/tokens.dart`. Never let them drift —
   goldens will fail.
2. **No gate, no merge.** CI blocks on: `flutter analyze` (zero issues),
   `flutter test` (all 80), golden diff, `bun run typecheck`,
   `bun test --coverage` (≥90% overall / ≥95% `src/auth/middleware.ts`),
   Gitleaks, dependency audits.
3. **Tests travel with the change.** New component → widget test + goldens.
   New endpoint → 4-way auth-matrix cases + happy path.
4. **$0 philosophy.** No new dependency or service that costs money or
   requires an account to develop against.

## Getting started

```bash
# App
cd stilora && flutter pub get && flutter test

# API
cd api && bun install && bun test
```

Local Postgres for the API: `docker compose up -d` in `api/` (or create a
free Neon branch). No accounts are needed to run either test suite.

## Pull request checklist

- [ ] `flutter analyze` → *No issues found!*
- [ ] `flutter test` → all green (update goldens ONLY with intent:
      `flutter test --update-goldens test/goldens`)
- [ ] `cd api && bun run typecheck && bun test --coverage` → green, gates met
- [ ] New/changed screens documented in DESIGN.md screen inventory
- [ ] Both themes checked (toggle in Settings → Appearance)
- [ ] Reduced-motion respected by any new animation
- [ ] No secrets, keys, or personal data in commits

## Commit style

Anything short and imperative works: `fix(capsule): pill no longer overlaps
avatars`, `feat(threads): reply view`, `chore(ci): add gitleaks`.

## Where things live

| Change | Files |
|---|---|
| Colors / type / spacing | `aura/DESIGN.md` → `stilora/lib/src/theme/tokens.dart` |
| Motion | `stilora/lib/src/theme/motion.dart` |
| Reusable widgets | `stilora/lib/src/widgets/` |
| Screens | `stilora/lib/src/screens/` |
| API endpoints | `api/src/routes/*.routes.ts` (+ tests!) |
| Security rules | `api/src/auth/middleware.ts` (touch carefully) |
