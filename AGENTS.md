# Repository Guidelines

## Project Structure & Module Organization
- `ClipboardCore/`: Swift package with Core Data model, business rules, and persistence.
  - `ClipboardCore/Sources/DataModel/`: `Paste.xcdatamodeld`, generated classes, and compiled `Paste.momd`.
  - `ClipboardCore/Sources/BusinessRules/`: `ClipItemStore`, payloads, retention.
  - `ClipboardCore/Sources/Assets/`: `AssetStore` for file-backed assets.
  - `ClipboardCore/Tests/ClipboardCoreTests/`: XCTest unit tests.
- `ClipboardMac/`: Swift package for the macOS app and services.
  - `ClipboardMac/Sources/ClipboardMacApp/`: App/UI (overlay, menu bar).
  - `ClipboardMac/Sources/ClipboardMacServices/`: Pasteboard monitor, extractor, thumbnails.
  - `ClipboardMac/Sources/ClipboardMacValidation/`: CLI validation runs.
  - `ClipboardMac/Tests/ClipboardMacTests/`: Services/integration tests.
  - `ClipboardMac/Tests/ClipboardMacAppTests/`: App/UI tests.
- `docs/`: Specs, phase plans, and status tracking.

## Build, Test, and Development Commands
- `cd ClipboardCore && swift build` — build the core library.
- `cd ClipboardCore && swift test` — run core unit tests.
- `cd ClipboardCore && swift test --enable-code-coverage` — measure coverage (see `ClipboardCore/.build/.../codecov/ClipboardCore.json`).
- `cd ClipboardMac && swift build` — build the macOS app + services.
- `cd ClipboardMac && swift test` — run app/services tests.
- `cd ClipboardMac && swift run ClipboardMac` — launch the app.
- `cd ClipboardMac && swift run ClipboardMacValidation` — run perf/validation metrics.
- If `Paste.xcdatamodeld` changes: `xcrun momc ClipboardCore/Sources/DataModel/Paste.xcdatamodeld ClipboardCore/Sources/DataModel/Paste.momd`.

## Coding Style & Naming Conventions
- Swift: 4-space indentation, braces on the same line.
- Types: `UpperCamelCase`; properties/functions: `lowerCamelCase`.
- Keep SwiftUI view names descriptive (e.g., `OverlayRootView`, `ItemCardRow`).
- No formatter is enforced; follow surrounding file style.

## Testing Guidelines
- XCTest is the default framework.
- Test names start with `test...` and cover a single behavior.
- Coverage target for Phase 2 is 75%+ (ClipboardCore currently 86.63% line coverage).

## Commit & Pull Request Guidelines
- Git history has a single commit; no established convention yet.
- Use concise, imperative commit messages (e.g., "Add paste engine metrics").
- PRs should include: summary, tests run, and doc updates (especially `docs/INDEX.md`).
- If Core Data changes, note migration impact and the updated `Paste.momd`.

## Architecture & Specs
- Start with `docs/INDEX.md` and `docs/specs/Architecture-Overview.md`.
- Phase status and checklists live in `docs/phase-2-plan.md` and `docs/INDEX.md`.
