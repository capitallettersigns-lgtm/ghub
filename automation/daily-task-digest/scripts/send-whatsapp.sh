#!/usr/bin/env bash
#
# send-whatsapp.sh — attach a PDF to a WhatsApp chat (by phone number) and send it,
# by driving the native WhatsApp Mac app with deterministic UI automation.
#
# Usage:
#   send-whatsapp.sh <absolute-pdf-path> <+E164number> [caption] [paste|attach] [delaySeconds]
#
# This is the inherently fragile part of the system: the WhatsApp Mac app has no
# scripting API, so we simulate keystrokes via System Events. Expect to tune the
# steps/delays below for your WhatsApp version the first time. See README "Tuning
# the WhatsApp step".
#
set -euo pipefail

PDF="${1:?usage: send-whatsapp.sh <pdf> <+number> [caption] [method] [delay]}"
NUMBER="${2:?missing WhatsApp number (+E164, e.g. +15551234567)}"
CAPTION="${3:-}"
METHOD="${4:-paste}"
DELAY="${5:-2}"

if [ ! -f "$PDF" ]; then
  echo "send-whatsapp: PDF not found: $PDF" >&2
  exit 1
fi

# osascript reads the script from stdin (quoted heredoc => no shell interpolation,
# so captions/paths with quotes are safe) and receives values as argv.
/usr/bin/osascript - "$PDF" "$NUMBER" "$CAPTION" "$METHOD" "$DELAY" <<'APPLESCRIPT'
on run argv
	set pdfPath to item 1 of argv
	set vaNumber to item 2 of argv
	set caption to item 3 of argv
	set sendMethod to item 4 of argv
	set baseDelay to (item 5 of argv) as real

	-- For the "paste" method, put the PDF on the clipboard as a file reference.
	if sendMethod is "paste" then
		tell application "Finder" to set the clipboard to (POSIX file pdfPath as alias)
	end if

	tell application "WhatsApp" to activate
	delay baseDelay

	tell application "System Events"
		tell process "WhatsApp"
			set frontmost to true
			delay 0.5

			-- Open "New chat" search and go to the VA by exact phone number.
			-- (⌘N opens new-chat search in current WhatsApp Mac builds; tune if yours differs.)
			keystroke "n" using command down
			delay baseDelay
			keystroke vaNumber
			delay baseDelay
			key code 36 -- Return: open the top matching contact
			delay baseDelay

			if sendMethod is "paste" then
				-- Paste the file into the message box; WhatsApp shows a document preview.
				keystroke "v" using command down
				delay (baseDelay + 1)
				if caption is not "" then
					keystroke caption
					delay 0.5
				end if
				key code 36 -- Return: send

			else
				-- "attach" method: open the attachment Open-panel, then type the path.
				-- NOTE: clicking the "+"/paperclip + choosing "Document" is version-specific.
				-- Tune the two lines below to open the file picker on your build, then the
				-- ⌘⇧G path entry is reliable.
				--
				-- (example, tune for your version:)
				-- click button "Attach" of group 1 of ...
				-- click menu item "Document" of menu 1 of ...
				delay baseDelay
				keystroke "g" using {command down, shift down} -- "Go to folder" in the Open panel
				delay 0.5
				keystroke pdfPath
				delay 0.5
				key code 36 -- confirm the typed path
				delay 0.5
				key code 36 -- open / choose the file
				delay (baseDelay + 1)
				if caption is not "" then
					keystroke caption
					delay 0.5
				end if
				key code 36 -- Return: send
			end if
		end tell
	end tell
end run
APPLESCRIPT

echo "send-whatsapp: sequence completed for $NUMBER"
