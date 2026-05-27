#!/usr/bin/env python3
"""Migrate Quip documents, spreadsheets, folders, and images to Apple Notes."""

from __future__ import annotations
import logging
import os
import tempfile
import re
import sys
import json
import time
import base64
import subprocess
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from html import escape as html_escape

# ── Config ────────────────────────────────────────────────────────────────────

QUIP_TOKEN = os.environ.get("QUIP_TOKEN", "")
QUIP_BASE = "https://platform.quip-apple.com/1"
RATE_DELAY = 0.5        # seconds between API calls
APPLE_NOTES_ACCOUNT = ""  # leave blank to use default account
OUTPUT_CACHE = Path("./cache")  # local cache for blobs
LOG_FILE = Path("./migrate.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# ── Quip API ──────────────────────────────────────────────────────────────────

def quip_get(path: str, binary: bool = False):
    url = f"{QUIP_BASE}{path}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {QUIP_TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.read() if binary else json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"Quip API {e.code} for {path}: {body}") from e


def get_current_user():
    return quip_get("/users/current")


def get_folder(folder_id: str):
    return quip_get(f"/folders/{folder_id}")


def get_thread(thread_id: str):
    return quip_get(f"/threads/{thread_id}")


def get_blob(thread_id: str, blob_hash: str) -> bytes:
    return quip_get(f"/threads/{thread_id}/blob/{blob_hash}", binary=True)


def trash_thread(thread_id: str, trash_folder_id: str) -> None:
    url = f"{QUIP_BASE}/folders/add-members"
    data = urllib.parse.urlencode({"folder_id": trash_folder_id, "member_ids": thread_id}).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={"Authorization": f"Bearer {QUIP_TOKEN}"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req):
            pass
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"Quip trash {e.code} for {thread_id}: {body}") from e


def is_shared(thread: dict, current_user_id: str) -> bool:
    """Return True if the thread is shared with anyone other than the owner."""
    member_ids = thread.get("member_ids", [])
    if not member_ids:
        return True  # unknown sharing status — don't delete
    if any(m != current_user_id for m in member_ids):
        return True
    sharing = thread.get("sharing", {})
    if sharing.get("company_mode", "NONE") != "NONE":
        return True
    return False


# ── Image handling ────────────────────────────────────────────────────────────

def strip_leading_heading_if_matches(html: str, title: str) -> str:
    """Remove the first heading from html only if its text matches the document title."""
    m = re.match(r'\s*<h[1-6][^>]*>(.*?)</h[1-6]>\s*', html, re.IGNORECASE | re.DOTALL)
    if m:
        heading_text = re.sub(r'<[^>]+>', '', m.group(1)).strip()
        if heading_text.lower() == title.lower():
            return html[m.end():]
    return html


def inline_images(html: str, thread_id: str) -> str:
    """Replace Quip blob URLs with base64 data URIs."""
    # Quip image src format: /blob/<thread_id>/<hash>  or full URL
    blob_pattern = re.compile(
        r'src="(?:https://platform\.quip\.com/1)?/blob/([A-Za-z0-9]+)/([A-Za-z0-9]+)"'
    )

    def replace_blob(m):
        tid, blob_hash = m.group(1), m.group(2)
        cache_path = OUTPUT_CACHE / tid / blob_hash
        if cache_path.exists():
            data = cache_path.read_bytes()
        else:
            try:
                data = get_blob(tid, blob_hash)
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_bytes(data)
                time.sleep(RATE_DELAY)
            except RuntimeError as e:
                log.warning("Could not fetch blob %s: %s", blob_hash, e)
                return m.group(0)
        b64 = base64.b64encode(data).decode()
        # Guess mime type from magic bytes
        mime = "image/png" if data[:4] == b"\x89PNG" else "image/jpeg"
        return f'src="data:{mime};base64,{b64}"'

    return blob_pattern.sub(replace_blob, html)


# ── AppleScript helpers ───────────────────────────────────────────────────────

def _esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


class OsaScript:
    _account = f'account "{APPLE_NOTES_ACCOUNT}"' if APPLE_NOTES_ACCOUNT else "default account"

    @staticmethod
    def _run(script: str) -> str:
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"osascript error: {result.stderr.strip()}")
        return result.stdout.strip()

    @staticmethod
    def _run_file(script: str) -> str:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".applescript", delete=False) as f:
            f.write(script)
            tmp = f.name
        try:
            result = subprocess.run(["osascript", tmp], capture_output=True, text=True)
            if result.returncode != 0:
                raise RuntimeError(f"osascript error: {result.stderr.strip()}")
            return result.stdout.strip()
        finally:
            os.unlink(tmp)

    @classmethod
    def _find_or_create_steps(cls, path: list[str]) -> str:
        """
        Generate AppleScript that walks `path` level by level, using the
        `container` property to scope each lookup to the correct parent.
        Leaves `curFolder` pointing at the final folder and returns its id.
        """
        lines = [
            f"set acct to {cls._account}",
            "set parentObj to acct",
        ]
        for name in path:
            lines += [
                f'set matchFolders to every folder of acct whose name is "{_esc(name)}"',
                "set curFolder to missing value",
                "repeat with f in matchFolders",
                "    if container of f is parentObj then",
                "        set curFolder to f",
                "        exit repeat",
                "    end if",
                "end repeat",
                "if curFolder is missing value then",
                f'    set curFolder to make new folder with properties {{name:"{_esc(name)}"}} at parentObj',
                "end if",
                "set parentObj to curFolder",
            ]
        lines.append("return id of curFolder")
        return "\n    ".join(lines)

    @classmethod
    def get_or_create_folder(cls, path: list[str]) -> str:
        """Find or create the folder at `path`; returns its Notes persistent ID."""
        return cls._run(f"""
tell application "Notes"
    {cls._find_or_create_steps(path)}
end tell
""")

    @classmethod
    def note_exists(cls, title: str, folder_id: str) -> bool:
        return cls._run(f"""
tell application "Notes"
    set theFolder to folder id "{_esc(folder_id)}" of {cls._account}
    return (count of (every note of theFolder whose name is "{_esc(title)}")) > 0
end tell
""") == "true"

    @classmethod
    def create_note(cls, title: str, html_body: str, folder_id: str) -> None:
        cls._run_file(f"""
tell application "Notes"
    set theFolder to folder id "{_esc(folder_id)}" of {cls._account}
    make new note at theFolder with properties {{body:"{_esc(html_body)}"}}
end tell
""")

    @classmethod
    def rename_note(cls, old_title: str, new_title: str, folder_id: str) -> None:
        cls._run(f"""
tell application "Notes"
    set theFolder to folder id "{_esc(folder_id)}" of {cls._account}
    set theNote to first note of theFolder whose name is "{_esc(old_title)}"
    set name of theNote to "{_esc(new_title)}"
end tell
""")


# ── Migration logic ───────────────────────────────────────────────────────────

def migrate_thread(thread_id: str, notes_path: list[str], notes_folder_id: str, visited: set, current_user_id: str, trash_folder_id: str) -> None:
    if thread_id in visited:
        return
    visited.add(thread_id)

    time.sleep(RATE_DELAY)
    try:
        data = get_thread(thread_id)
    except RuntimeError as e:
        log.error("Failed to fetch thread %s: %s", thread_id, e)
        return

    thread = data.get("thread", {})
    title = thread.get("title", "Untitled")
    html = data.get("html", "") or ""

    created_usec = thread.get("created_usec", 0)
    if created_usec:
        created_dt = datetime.fromtimestamp(created_usec / 1_000_000, tz=timezone.utc)
        created_str = created_dt.strftime("%m/%d/%Y")
    else:
        created_str = "Unknown"

    shared = is_shared(thread, current_user_id)
    note_title = f"{title} (Private)" if not shared else title
    quip_link = thread.get("link", "")

    html = strip_leading_heading_if_matches(inline_images(html, thread_id), title)

    link_line = f'<p><em>Quip Link: <a href="{html_escape(quip_link)}">{html_escape(quip_link)}</a></em></p>' if quip_link else ""

    full_html = (
        f"<html><body>"
        f"<h1>{html_escape(note_title)}</h1>"
        f"<p><em>Created in Quip: {created_str}</em></p>"
        f"<p><em>From Quip Folder: {html_escape(' / '.join(notes_path[1:]))}</em></p>"
        f"{link_line}"
        f"<hr/>"
        f"{html}"
        f"</body></html>"
    )

    try:
        if OsaScript.note_exists(note_title, notes_folder_id):
            log.info("  [skipped]  %s", note_title)
            return
        OsaScript.create_note(note_title, full_html, notes_folder_id)
        log.info("  [copied]   %s  (created %s)", note_title, created_str)
    except RuntimeError as e:
        log.error("  [error]    %s — %s", note_title, e)
        return

    if not shared:
        try:
            time.sleep(RATE_DELAY)
            trash_thread(thread_id, trash_folder_id)
            trashed_title = f"{note_title} (Trashed in Quip)"
            OsaScript.rename_note(note_title, trashed_title, notes_folder_id)
            log.info("  [trashed]  %s", trashed_title)
        except RuntimeError as e:
            log.warning("  [error]    %s — could not trash in Quip: %s", note_title, e)


def migrate_folder(folder_id: str, notes_path: list[str], visited_folders: set, visited_threads: set, current_user_id: str, trash_folder_id: str) -> None:
    if folder_id in visited_folders:
        return
    visited_folders.add(folder_id)

    time.sleep(RATE_DELAY)
    try:
        data = get_folder(folder_id)
    except RuntimeError as e:
        log.error("Failed to fetch folder %s: %s", folder_id, e)
        return

    folder_info = data.get("folder", {})
    folder_name = folder_info.get("title", f"Quip-{folder_id}")
    children = data.get("children", [])
    folder_path = notes_path + [folder_name]

    log.info("Folder: %s", " / ".join(folder_path))
    notes_folder_id = OsaScript.get_or_create_folder(folder_path)

    for child in children:
        if "thread_id" in child:
            migrate_thread(child["thread_id"], folder_path, notes_folder_id, visited_threads, current_user_id, trash_folder_id)
        elif "folder_id" in child:
            migrate_folder(child["folder_id"], folder_path, visited_folders, visited_threads, current_user_id, trash_folder_id)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    if not QUIP_TOKEN:
        log.error("Set the QUIP_TOKEN environment variable to your Quip API token.")
        log.error("Get one at: https://quip-apple.com/dev/token")
        sys.exit(1)

    OUTPUT_CACHE.mkdir(exist_ok=True)

    log.info("Fetching current user...")
    try:
        user = get_current_user()
    except RuntimeError as e:
        log.error("Auth failed: %s", e)
        sys.exit(1)

    name = user.get("name", "Unknown")
    current_user_id = user.get("id", "")
    trash_folder_id = user.get("trash_folder_id", "")
    log.info("Authenticated as: %s (%s)", name, current_user_id)

    # The user's desktop and starred folders are the roots
    desktop_id = user.get("desktop_folder_id")
    starred_id = user.get("starred_folder_id")
    shared_ids = user.get("shared_folder_ids", [])

    root_ids = [fid for fid in [desktop_id, starred_id] + shared_ids if fid]

    visited_folders: set = set()
    visited_threads: set = set()

    OsaScript.get_or_create_folder(["From Quip"])

    for fid in root_ids:
        migrate_folder(fid, ["From Quip"], visited_folders, visited_threads, current_user_id, trash_folder_id)

    log.info("Done. Migrated %d documents across %d folders.", len(visited_threads), len(visited_folders))


if __name__ == "__main__":
    main()
