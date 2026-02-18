#!/bin/bash
MEMO_FILE="$HOME/Documents/memos.md"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
echo "" >> "$MEMO_FILE"
echo "## $TIMESTAMP" >> "$MEMO_FILE"
echo "$OPENTOLK_INPUT" >> "$MEMO_FILE"
echo "Memo saved."
