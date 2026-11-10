# AGENTS.md — Quip Exporter

Quip Exporter is a SwiftUI macOS app (Swift package, macOS 13+) that exports Quip documents, spreadsheets, and folders to Apple Notes, Numbers, CSV, Markdown, or HTML. See [docs/README.md](docs/README.md).

## Commands

- `make test-quick`: fast unit tests with no AppleScript or UI. Run this after every change.
- `make test`: the full suite, including tests that drive the real Notes and Numbers apps (`RUN_UI_TESTS=1`); it may prompt for Automation access.
- `make dev`: quit, rebuild, and relaunch the debug app.
- `make publish`: release bundle. `make install` / `make uninstall` / `make reinstall`: manage `/Applications`.
- `make test-note`, `make test-markdown-import`, `make test-numbers`: targeted end-to-end checks for each exporter.
- `make help` lists everything.

## Layout

- `Sources/QuipExporter/MigrationEngine.swift`, `MigrationRunner.swift`: walk the Quip folder tree and run exports.
- `Sources/QuipExporter/External/`: Quip API client and the Notes, Numbers, and file writers.
- `Sources/QuipExporter/Views/`: SwiftUI UI.
- `Tests/QuipExporterTests/`: XCTest suite. UI/AppleScript tests are gated behind `RUN_UI_TESTS`.
- `scripts/`: icon generation and Numbers debugging helpers.

## Conventions

- Tests that open Notes or Numbers must stay behind `RUN_UI_TESTS` so `make test-quick` stays headless.
- Never log the Quip API token or include it in exported files.
- Exports must not modify or delete anything in Quip.

## Design principles

Follow the [design principles](docs/rules/design-principles.md) for any UI work.

## After changing code

1. `make test-quick`
2. `make dev`

Commit messages are one short, imperative line, like the existing history.
