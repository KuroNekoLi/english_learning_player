---
name: english-learning-player-engineering
description: Build, refactor, debug or review this Flutter Android/iOS/macOS/Web English listening app, including M4A/MP3 playback, bilingual SRT alignment, offline sync, Firebase, iCloud folder monitoring and cross-device progress. Load for any task inside this repo.
---

# English Learning Player — Project Engineering Skill

## Before changing code
1. Read repository `AGENTS.md` and `docs/README.md`.
2. Identify exactly one `WP-xx` from `docs/11-work-packages.md` and read only the corresponding domain spec.
3. Check actual Git working tree and the current installed Flutter/Dart SDK; do not assume dependencies or cloud credentials exist.
4. Invoke relevant official Flutter/Dart Skills under `.agents/skills/` for architecture, widgets, responsive UI, unit tests and analyzer.
5. State inputs, processing logic, outputs and failure behavior before implementation.

## Implementation rules
- Use Riverpod to wire immutable ViewModel states; Flutter widgets only render and forward events.
- Keep `AudioEngine` as the sole playback gateway, test `just_audio` behind a fake.
- Treat SRT parser, filename matcher, cue time aligner, repeat, progress resolver as isolated pure Dart units.
- Use integer milliseconds and half-open intervals `[startMs,endMs)`; preserve original SRT and manual overrides.
- Repository controls SQLite local source of truth, cloud operations flow via durable Outbox with idempotency and retry.
- Firebase Auth UID scopes every private resource; verify Security Rules in emulator; do not log private SRT bodies or tokens.
- Native iCloud folder selection must be user-authorized and security-scoped, Mac only for MVP; do not promise arbitrary iOS background sync.
- No changes to source iCloud files, no deletion of cloud study material merely because a source file disappeared.
- For native or platform claims, cite real builds/devices; fake-only tests are not platform verification.

## Editorial Reader UI tasks
- Load `docs/15-editorial-design-system.md`, `docs/design-system/editorial-tokens.json` and `docs/agent/wp-22-editorial-handoff.md` in addition to the relevant domain spec.
- Reuse EditorialTheme, EditorialColors, EditorialTypography, spacing/radius/size tokens and EditorialLanguageControl / EditorialListRow / EditorialPageHeading. Keep brand literals inside the design system; use the existing official sign-in assets unchanged.
- Keep playback state, intensive reveal rules, exact-word highlighting, per-cue translation, persisted subtitle appearance, authentication/read-only and sync contracts intact. Theme preference is device-local; do not sync it implicitly.
- Test both themes, constrained widths, system text scaling, keyboard/semantics and color contrast. Review rendered Golden diffs before accepting changes; do not regenerate unrelated baselines.
- User-confirmed visual baseline v1.0 is not a release gate PASS. Check WP-22 handoff for outstanding platform builds, accessibility and pre-existing T-FOLDER-08.

## Completion report
Include `WP ID`, files touched, tests run with observed outputs, FR/T-ID mapping, ADR changes, PASS/FAIL/BLOCKED and one recommended next WP. Do not claim unexecuted work succeeded or commit/push without permission.
