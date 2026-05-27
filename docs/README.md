# Quip Exporter

A macOS app that migrates Quip documents, spreadsheets, and folders to Apple Notes or Markdown files.

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

**Apple Notes** — creates a top-level "From Quip" folder in Notes, preserving the Quip folder hierarchy.

**Markdown** — saves each document as a `.md` file in a chosen output folder, with images in an `_assets/` subfolder alongside each file.

## Notes

- Images are cached in `~/Library/Application Support/QuipExporter/BlobCache/` to avoid re-downloading on re-runs.
- Shared documents are copied but not trashed in Quip even when "delete after copy" is enabled.
- The app uses AppleScript to drive Apple Notes — no third-party dependencies required.
