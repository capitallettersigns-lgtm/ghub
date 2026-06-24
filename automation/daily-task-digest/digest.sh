#!/usr/bin/env bash
#
# digest.sh — one place to install, manage, test, and tweak the daily routine.
# You shouldn't need to touch the launchd plist or remember launchctl flags.
#
#   ./digest.sh install        generate + load the daily schedule (from config.json)
#   ./digest.sh uninstall      remove the schedule
#   ./digest.sh disable        pause (unload) without removing
#   ./digest.sh enable         resume after disable
#   ./digest.sh status         installed? loaded? sent today? + recent log
#   ./digest.sh run            run the whole routine now (capture + send)
#   ./digest.sh capture        capture today's PDF only, then open it (test the selector)
#   ./digest.sh send-test [n]  send the latest PDF to a number (default your VA) — tune WhatsApp
#   ./digest.sh logs           tail today's run log
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true

LABEL="com.user.daily-task-digest"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

read_cfg() {
  node --input-type=commonjs -e \
    "const c=JSON.parse(require('fs').readFileSync('./config.json','utf8'));process.stdout.write(String(($1)??''))" 2>/dev/null
}

need_config() { [ -f config.json ] || { echo "config.json not found — copy config.example.json to config.json first."; exit 1; }; }
need_build()  { [ -f dist/capture.js ] || { echo "Not built yet — run: npm install && npm run build"; exit 1; }; }

cmd_install() {
  need_config; need_build
  local hour minute
  hour="$(read_cfg '(c.schedule&&c.schedule.hour)??7')"
  minute="$(read_cfg '(c.schedule&&c.schedule.minute)??0')"
  mkdir -p "$HOME/Library/LaunchAgents" logs

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$DIR/run.sh</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$DIR/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$DIR/logs/launchd.err.log</string>
</dict>
</plist>
EOF

  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
  printf 'Installed. Scheduled daily at %02d:%02d (from config.json).\n' "$hour" "$minute"
  echo "Plist: $PLIST"
  echo "Tip: run it once now with  ./digest.sh run"
}

cmd_uninstall() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled — the daily schedule is removed."
}

cmd_enable() {
  [ -f "$PLIST" ] || { echo "Not installed yet — run: ./digest.sh install"; exit 1; }
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
  echo "Enabled."
}

cmd_disable() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  echo "Disabled (paused). Resume with: ./digest.sh enable"
}

cmd_status() {
  echo "Label:     $LABEL"
  [ -f "$PLIST" ] && echo "Installed: yes  ($PLIST)" || echo "Installed: no  (run: ./digest.sh install)"
  launchctl list 2>/dev/null | grep -q "$LABEL" && echo "Loaded:    yes" || echo "Loaded:    no"
  if [ -f config.json ]; then
    local hour minute
    hour="$(read_cfg '(c.schedule&&c.schedule.hour)??7')"; minute="$(read_cfg '(c.schedule&&c.schedule.minute)??0')"
    printf 'Scheduled: %02d:%02d daily (from config.json)\n' "$hour" "$minute"
  fi
  local today; today="$(date +%F)"
  [ -f "state/sent-$today.flag" ] && echo "Today:     SENT ($today)" || echo "Today:     not sent yet ($today)"
  local latest; latest="$(ls -t logs/run-*.log 2>/dev/null | head -1 || true)"
  if [ -n "$latest" ]; then echo; echo "Last run log ($latest):"; tail -n 8 "$latest" | sed 's/^/  /'; fi
  local fail; fail="$(ls -t logs/failure-*.png 2>/dev/null | head -1 || true)"
  [ -n "$fail" ] && { echo; echo "Most recent failure screenshot: $fail"; }
}

cmd_run() { need_config; need_build; bash run.sh; }

cmd_capture() {
  need_config; need_build
  node dist/capture.js
  local pdf="out/today-$(date +%F).pdf"
  [ -f "$pdf" ] && { echo "Opening $pdf"; open "$pdf" 2>/dev/null || true; }
}

cmd_send_test() {
  need_config; need_build
  local to="${1:-$(read_cfg 'c.whatsapp&&c.whatsapp.vaNumber')}"
  [ -n "$to" ] || { echo "Give a number (./digest.sh send-test +1555...) or set whatsapp.vaNumber."; exit 1; }
  local pdf; pdf="$(ls -t out/*.pdf 2>/dev/null | head -1 || true)"
  if [ -z "$pdf" ]; then echo "No PDF in out/ — capturing one first..."; node dist/capture.js; pdf="out/today-$(date +%F).pdf"; fi
  local caption method delay
  caption="$(read_cfg 'c.whatsapp&&c.whatsapp.caption')"
  method="$(read_cfg '(c.whatsapp&&c.whatsapp.sendMethod)||"paste"')"
  delay="$(read_cfg '(c.whatsapp&&c.whatsapp.delaySeconds)||2')"
  echo "Sending $pdf -> $to  (method=$method, delay=$delay)"
  bash scripts/send-whatsapp.sh "$DIR/$pdf" "$to" "$caption" "$method" "$delay"
}

cmd_logs() {
  local latest; latest="$(ls -t logs/run-*.log 2>/dev/null | head -1 || true)"
  [ -n "$latest" ] && { echo "tail -f $latest"; tail -f "$latest"; } || echo "No run logs yet."
}

case "${1:-}" in
  install)    cmd_install ;;
  uninstall)  cmd_uninstall ;;
  enable)     cmd_enable ;;
  disable)    cmd_disable ;;
  status)     cmd_status ;;
  run)        cmd_run ;;
  capture)    cmd_capture ;;
  send-test)  shift; cmd_send_test "${1:-}" ;;
  logs)       cmd_logs ;;
  *)
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
