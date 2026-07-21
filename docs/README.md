# Quip Exporter

A macOS app that migrates Quip documents, spreadsheets, and folders to Apple Notes, Numbers, CSV, Markdown, or HTML.

## Download

[Download QuipExporter.zip](https://github.pie.apple.com/a-vaos/quip-export/releases/latest/download/QuipExporter.zip)

## How it works

The app walks your Quip account starting from the Desktop, Starred, and Shared folder roots. For each document it finds, it:

1. Fetches the thread HTML via the Quip API
2. Downloads and caches any blob images
3. Creates a matching folder hierarchy in the destination
4. Exports the note, skipping any already-exported documents on re-runs

## Prerequisites

- macOS 13+
- A Quip API token from <https://quip-apple.com/dev/token>

## Build

```sh
make open
```

## Export destinations

Documents and spreadsheets each have their own destination setting, configured independently.

**Apple Notes** — creates a top-level "From Quip" folder in Notes, preserving the Quip folder hierarchy. Available for documents and spreadsheets.

**Numbers** — saves each spreadsheet as a native `.numbers` file in a chosen output folder, one sheet per Quip tab. Spreadsheets only.

**CSV** — saves each spreadsheet as a folder (named after the document) of `.csv` files, one per Quip tab. Spreadsheets only.

**Markdown** — saves each document as a `.md` file in a chosen output folder, with images in an `_assets/` subfolder alongside each file.

**HTML** — saves each document as a standalone `.html` file in a chosen output folder, with images in an `_assets/` subfolder alongside each file.

**Ask** — prompts for a destination each time a document or spreadsheet is exported.

## Notes

- Images are cached in `~/Library/Application Support/QuipExporter/BlobCache/` to avoid re-downloading on re-runs.
- Shared documents are copied but not trashed in Quip even when "delete after copy" is enabled.
- The app uses AppleScript to drive Apple Notes and Numbers — no third-party dependencies required. macOS will prompt for Automation permission the first time each app is scripted. CSV export does not use AppleScript or require this permission.
