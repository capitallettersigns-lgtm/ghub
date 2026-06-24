#!/usr/bin/env bash
#
# run.sh — the daily routine: capture today's section to a PDF, then send it to the
# VA via the native WhatsApp Mac app. Designed to be launched unattended by launchd.
#
# On any failure it makes the problem LOUD (macOS notification + screenshot + log)
# instead of failing silently, and it won't send twice in one day.
#
set -uo pipefail

# Run from this script's own folder (so relative paths in config.json resolve).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# launchd runs with a minimal PATH — make common Node install locations visible.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# If you use nvm, load its default Node.
if [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; fi

DATE="$(date +%F)"
mkdir -p logs state out
LOG="logs/run-$DATE.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S') :: daily-task-digest start ==="

# Keep the Mac awake (no idle sleep) for as long as this run is alive.
caffeinate -i -w "$$" &

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Daily Task Digest\" sound name \"Basso\"" >/dev/null 2>&1 || true
}

fail() {
  local stage="$1" msg="$2"
  echo "ERROR [$stage]: $msg"
  /usr/sbin/screencapture -x "logs/failure-$DATE.png" >/dev/null 2>&1 || true
  notify "FAILED at ${stage}. See logs/run-${DATE}.log"
  exit 1
}

# Don't send twice in one day (e.g. if the job is triggered again).
if [ -f "state/sent-$DATE.flag" ]; then
  echo "Already sent today ($DATE). Nothing to do."
  exit 0
fi

if [ ! -f config.json ]; then
  fail "config" "config.json not found — copy config.example.json and fill it in"
fi
if [ ! -f dist/capture.js ]; then
  fail "build" "dist/capture.js not found — run 'npm install && npm run build' first"
fi

# Read WhatsApp settings out of config.json without needing jq.
read_cfg() {
  node --input-type=commonjs -e \
    "const c=JSON.parse(require('fs').readFileSync('./config.json','utf8'));process.stdout.write(String(($1)??''))"
}
VANUMBER="$(read_cfg 'c.whatsapp&&c.whatsapp.vaNumber')"
CAPTION="$(read_cfg 'c.whatsapp&&c.whatsapp.caption')"
METHOD="$(read_cfg '(c.whatsapp&&c.whatsapp.sendMethod)||"paste"')"
DELAY="$(read_cfg '(c.whatsapp&&c.whatsapp.delaySeconds)||2')"
[ -n "$VANUMBER" ] || fail "config" "whatsapp.vaNumber missing in config.json"

# 1) Capture today's section to a PDF.
echo "--- capture ---"
node dist/capture.js || fail "capture" "capture.js exited non-zero"
PDF="out/today-$DATE.pdf"
[ -s "$PDF" ] || fail "capture" "expected PDF missing or empty: $PDF"
echo "Captured $PDF ($(wc -c < "$PDF" | tr -d ' ') bytes)"

# 2) Send via the native WhatsApp Mac app.
echo "--- send ---"
bash scripts/send-whatsapp.sh "$DIR/$PDF" "$VANUMBER" "$CAPTION" "$METHOD" "$DELAY" \
  || fail "send" "send-whatsapp.sh exited non-zero"

# 3) Mark today done.
touch "state/sent-$DATE.flag"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') :: done; sent to ${VANUMBER} ==="
