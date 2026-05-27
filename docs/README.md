# quip-export

Migrates Quip documents, spreadsheets, folders, and images to Apple Notes.

## How it works

The script walks your Quip account starting from the desktop, starred, and shared folder roots. For each document it finds, it:

1. Fetches the thread HTML via the Quip API
2. Downloads and base64-inlines any blob images
3. Creates a matching folder hierarchy in Apple Notes under a top-level **From Quip** folder
4. Creates the note with the original HTML body, a creation date, folder path, and a link back to Quip
5. For private (unshared) documents, moves the Quip original to Trash and renames the Note to indicate it was trashed

Already-migrated notes are skipped on re-runs, so the script is safe to run multiple times.

## Prerequisites

- macOS with Apple Notes
- Python 3.9+
- A Quip API token from <https://quip-apple.com/dev/token>

## Setup

```sh
export QUIP_TOKEN=your_token_here
```

Optionally, set `APPLE_NOTES_ACCOUNT` at the top of `migrate.py` to target a specific Notes account (leave blank for the default account).

## Usage

```sh
python3 migrate.py
```

Progress is logged to stdout and to `migrate.log`.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `QUIP_TOKEN` | *(required)* | Quip API bearer token |
| `APPLE_NOTES_ACCOUNT` | `""` | Notes account name; blank = default |
| `RATE_DELAY` | `0.5s` | Pause between Quip API calls |
| `OUTPUT_CACHE` | `./cache` | Local cache for downloaded blobs |
| `LOG_FILE` | `./migrate.log` | Log file path |

## Notes

- Images are cached in `./cache/` to avoid re-downloading on subsequent runs.
- The script uses AppleScript (`osascript`) to drive Apple Notes — no third-party dependencies required.
- Shared documents are copied but **not** trashed in Quip.
