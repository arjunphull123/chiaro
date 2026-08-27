# Contributing to Chiaro

## Building

```
swift build && .build/debug/Chiaro   # debug build, straight to the app
scripts/bundle.sh                     # release build → dist/Chiaro.app
```

The dev harness gives fast, scriptable ways to drive a build without clicking
through the UI:

```
swift run Chiaro -- --open <folder> [--edit <name>] [--snapshot <png>] [--export-test <name>]
[--quiet (no focus steal)] [--click <x> <y-from-top> [n]] [--show-tips] [--show-export] [--download-depth]
[--render-icon <png>] [--render-depth-scene <name> <png>] [--auto-test <name>]
[--greeting <text> (pins the clock-derived start-screen salutation)]
```

After any app-code change, refresh the installed copy so the version in
`/Applications` matches what you built:

```
scripts/bundle.sh && rm -rf /Applications/Chiaro.app && cp -R dist/Chiaro.app /Applications
```

## Running the tests

```
scripts/test.sh
```

That is `swift test` with a full Xcode install. With Command Line Tools alone,
SwiftPM does not find Testing.framework, and the script supplies its paths.

The `ChiaroTests` target is the unit suite over Chiaro's pure logic: `EditState`
serialization, sidecar read/write and placement, the MCP server's Origin check,
library enumeration, presets, the update check's version compare, the recent-card
cache, and a render smoke test. It doesn't cover rendering or UI; verify those by running the app
itself with the dev harness above.

## Where things live

- `Sources/Chiaro/Engine`: RAW decode, the render pipeline, color grading,
  depth, portrait blur, stats
- `Sources/Chiaro/MCP`: the local MCP server
- `Sources/Chiaro/Models`: `EditState`, `Photo`, `Library`, presets
- `Sources/Chiaro/Persistence`: sidecar files, recent-card storage
- `Sources/Chiaro/Resources`: fonts, the app icon, the bundled `chiaro-editing`
  skill served over MCP
- `Sources/Chiaro/Support`: dev harness, resource lookup, small platform glue
- `Sources/Chiaro/Views`: SwiftUI views and the design system
- `docs/adr`: architectural decisions, including the ones that got cut

## Conventions

Full detail is in `CLAUDE.md`; the short version:

- **Lean code.** Comments only for constraints the code can't express, no
  narration, no restating the obvious.
- **Every edit operation is a value in `EditState`.** Serializable, diffable,
  programmatically settable. This is what keeps sidecar persistence,
  copy/paste edits, undo, and MCP editing all trivial, so new edit operations
  must go through it rather than living in view state.
- **ADRs for anything architectural.** Changes to structure, dependencies, or
  data formats get a numbered record in `docs/adr/`. Small implementation
  choices don't need one.
- Prefer Apple frameworks over third-party packages; a new dependency needs an
  ADR justifying it.
- **Buttons come from `DesignSystem.swift`** (Amber, Outline, Glass, GlassIcon,
  Chip). Ad-hoc button chrome is a bug.
- **Typography:** Fraunces is the wordmark only; Archivo ExtraBold is for
  display headlines; Geist is all UI text; Geist Mono is for data values only
  (EXIF, counts, timestamps).
- **UI copy** is sentence case, no trailing periods on labels or tips, never
  all-lowercase.

## Proposing changes

Open an issue first for anything architectural, or anything that adds a new
dependency, so the direction can be discussed before code is written. Small,
self-contained fixes can go straight to a pull request.

Post-release, changes land on feature branches; `main` is released history.

## Scope

Before proposing a feature, check the "Considered and deliberately not
planned" list near the end of `docs/ROADMAP.md`. Those items were left out on
purpose, mostly because they conflict with a hard rule elsewhere (freehand
brush masks, for instance, would break the one-readable-sidecar model in ADR
0002), not because nobody thought of them.

## The agent surface

The MCP tools and the bundled skill in `Sources/Chiaro/Resources/Skill` are
part of the product, not internal tooling: an agent driving Chiaro is a
first-class way to use the app. If a change touches a tool's schema or
behavior, note it in ADR 0008, or write a new ADR if the change is substantial
enough to warrant one.
