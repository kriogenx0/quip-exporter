#!/usr/bin/env bash
# Reusable Numbers AppleScript scratch-test runner, driven by `make test-numbers`.
# The test content and its title live in separate files that get edited between
# iterations while debugging Numbers scripting issues — just rerun the same
# `make test-numbers` command after each edit.
#
# Each run gets an incrementing test number (persisted in numbers-test-counter.txt)
# and is appended to numbers-test-log.txt, so there's always a clear record of which
# test ran when and what it found. The full output (including the invocation command
# itself) is also copied to the clipboard so it can be pasted straight back.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TITLE_FILE="$SCRIPT_DIR/numbers-test-title.txt"
SCRIPT_FILE="$SCRIPT_DIR/numbers-test.applescript"
COUNTER_FILE="$SCRIPT_DIR/numbers-test-counter.txt"
LOG_FILE="$SCRIPT_DIR/numbers-test-log.txt"

N=$(( $(cat "$COUNTER_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$COUNTER_FILE"

TITLE=$(cat "$TITLE_FILE" 2>/dev/null || echo "(no title set)")

SECONDS=0
RESULT=$(/usr/bin/osascript "$SCRIPT_FILE" 2>&1)
STATUS=$?
ELAPSED=$SECONDS

if [ $STATUS -eq 0 ]; then
    RESULT_LINE="PASS [$ELAPSED s]: $RESULT"
else
    RESULT_LINE="FAIL [$ELAPSED s]
error: $RESULT"
fi

DOCS=$(/usr/bin/osascript -e 'tell application "Numbers" to count of documents' 2>&1)

FULL_OUTPUT="make test-numbers
=== Test #$N: $TITLE ===
$RESULT_LINE

documents open now: $DOCS"

echo "$FULL_OUTPUT"
echo "$FULL_OUTPUT" | pbcopy

{
    echo "--- Test #$N ($(date '+%Y-%m-%d %H:%M:%S')) ---"
    echo "title: $TITLE"
    echo "$RESULT_LINE"
    echo "documents open now: $DOCS"
    echo
} >> "$LOG_FILE"
