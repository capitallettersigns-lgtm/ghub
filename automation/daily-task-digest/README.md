# daily-task-digest

Every morning, automatically:

1. **Capture** just **today's section** of a logged-in schedule page → a **PDF**.
2. **Send** that PDF to your VA through the **native WhatsApp Mac app**.

It runs **unattended** on your Mac via `launchd`, keeps the machine awake with
`caffeinate` while it works, and **never fails silently** — any problem triggers a
macOS notification + a screenshot in `logs/`.

No AI at run time, no API keys, no per-run cost. It's a deterministic routine: the
capture is done by a headless-capable browser that reuses your logged-in session, and
the send is done by scripted UI automation of the WhatsApp app you already have.

---

## How it works

| Piece | File | What it does |
|------|------|--------------|
| Capture | `src/capture.ts` → `dist/capture.js` | Opens the page in a **persistent, logged-in** Chromium profile, finds the header matching today's date, screenshots that section, writes `out/today-YYYY-MM-DD.pdf`. |
| Selector helper | `src/find-today-helper.ts` | Prints candidate day-header selectors so you can configure capture for *your* page. |
| Send | `scripts/send-whatsapp.sh` | Drives the WhatsApp Mac app (AppleScript / System Events) to open the VA's chat, attach the PDF, and send. |
| Orchestrator | `run.sh` | `caffeinate` + capture + send + failure alerts + "already sent today" guard. |
| Schedule | `com.user.daily-task-digest.plist` | `launchd` agent that runs `run.sh` at a set time each day. |

> ⚠️ **The WhatsApp step is the fragile part.** The Mac app has no scripting API, so
> sending is done by simulating keystrokes. It will likely need a little tuning for
> your WhatsApp version the first time (see [Tuning the WhatsApp step](#tuning-the-whatsapp-step)).
> The loud failure alert exists precisely so a broken morning is obvious, not silent.

---

## Prerequisites

- macOS, with the **WhatsApp Mac app** installed and signed in.
- **Node.js ≥ 20** (`node -v`). Install from nodejs.org or `brew install node`.
- Your Mac stays **on, logged in, and unlocked** at the scheduled time (see
  [Operational requirements](#operational-requirements)).

---

## One-time setup

### 1. Install

```bash
cd automation/daily-task-digest
npm install
npx playwright install chromium   # downloads the browser Playwright drives
npm run build
```

### 2. Configure

```bash
cp config.example.json config.json
```

Edit `config.json`:

- `url` — the schedule page (the one behind your login).
- `today.dateFormat` — **how today's date appears in the page's day header.** Tokens:
  `YYYY YY MMMM MMM MM M DD D dddd ddd`. Examples:
  - `"Wednesday, June 24"` → `"dddd, MMMM D"`
  - `"06/24/2026"` → `"MM/DD/YYYY"`
  - `"24 Jun"` → `"D MMM"`
- `capture.*` — how to crop today's section (see [Capture modes](#capture-modes)).
- `whatsapp.vaNumber` — the VA's number in full international form, e.g. `+15551234567`.
- `whatsapp.caption` — optional message sent with the PDF.
- `schedule.hour` / `schedule.minute` — when it runs (also set this in the plist, step 6).

### 3. Log in once (creates the persistent profile)

Run the capture once. A Chromium window opens using a dedicated profile stored in
`.profile/`. **Log into the web app in that window.** Your session persists there for
future runs.

```bash
npm run capture
```

Leave `headless: false` in `config.json` until everything works, so you can watch.

### 4. Find the right "today" selector

If capture can't find today's section (or grabs the wrong thing), inspect the page:

```bash
npm run find-today
```

It prints candidate selectors and marks (★) the element that currently contains
today's date. Put a reliable one in `capture.dateHeaderSelector` and pick a
[capture mode](#capture-modes). Re-run `npm run capture` and open the PDF in `out/`
until it shows **exactly today's section**.

### 5. Grant macOS permissions

The first send will prompt for permissions. Grant them in
**System Settings → Privacy & Security**:

- **Automation** → allow your terminal (or `bash`/`osascript`) to control **WhatsApp**
  and **System Events**.
- **Accessibility** → enable the app that runs the script (Terminal, or whatever
  `launchd` runs it as).
- **Screen Recording** → needed so the failure-screenshot (`screencapture`) isn't blank.

Test the send to **yourself first** (put your own number in `vaNumber`):

```bash
npm run build
bash scripts/send-whatsapp.sh "$PWD/out/today-$(date +%F).pdf" "+YOURNUMBER" "test" paste 2
```

### 6. Schedule it

`digest.sh` generates the launchd job **from your `config.json`** (no hand-editing
paths or `Hour`/`Minute` in a plist) and manages it:

```bash
chmod +x digest.sh
./digest.sh install     # generate + load the daily schedule (uses schedule.hour/minute)
./digest.sh run         # run the whole routine right now, to confirm the scheduled path
./digest.sh status      # installed? loaded? sent today? + tail of the last run log
```

Changed the time in `config.json`? Just run `./digest.sh install` again. See
[Managing & tweaking it](#managing--tweaking-it).

---

## Capture modes

Set `capture.mode` in `config.json`:

- **`container`** *(default)* — find the header matching today, then screenshot its
  surrounding box. Set `sectionContainerSelector` to the ancestor that wraps one day
  (e.g. `.day-card`); if empty, the header's parent is used. Best when each day is a
  card/section.
- **`element`** — screenshot the matched element itself. Use when
  `dateHeaderSelector` already targets the whole day block.
- **`clip-to-next-header`** — screenshot the region from today's header down to the
  next day's header. Use when days are a flat list with no per-day wrapper. Optionally
  set `contentColumnSelector` to bound the width.
- **`full-page`** — screenshot the entire page. Use when the page already shows only
  today.

---

## Operational requirements

These determine whether the **unattended** job actually works:

- **The Mac must be on, logged in, and ideally unlocked** at the scheduled time.
  GUI automation (focusing WhatsApp, the file picker) needs an active Aqua session;
  a locked **login window** will break it. `caffeinate` (built into `run.sh`) prevents
  idle sleep during the run, but it can't log you in. Tips: disable auto-lock, or keep
  the session unlocked; ensure "Put the Mac to sleep" won't fully sleep it (Energy
  settings / a persistent `caffeinate` overnight if you prefer).
- **WhatsApp must stay signed in** on the Mac app.
- Keep `config.json` and `.profile/` private — they hold your login. Both are
  git-ignored.

---

## Tuning the WhatsApp step

`scripts/send-whatsapp.sh` simulates this sequence:

1. `⌘N` → open new-chat search
2. type the VA's number → `Return` to open the chat
3. **paste** the PDF (`⌘V`) *or* open the **attach** Open-panel and type the path
4. optional caption → `Return` to send

If it misfires:

- **Increase `whatsapp.delaySeconds`** (slow machines need 3–4s).
- **`⌘N` opens the wrong thing** → change the shortcut in the AppleScript to match
  your build (some versions use the search field differently).
- **Paste doesn't attach the file** → switch `whatsapp.sendMethod` to `"attach"` and
  fill in the two commented `click` lines that open the attachment picker (the `⌘⇧G`
  path entry after that is reliable).
- **Wrong contact opens** → make sure `vaNumber` is the exact saved number; a stored
  contact name match is fuzzier than a number.

Run it by hand (not via launchd) while tuning so you can watch each step.

---

## Managing & tweaking it

Everything goes through `./digest.sh`, so you rarely touch the plist or remember
`launchctl`:

| Command | What it does |
|---|---|
| `./digest.sh install` / `uninstall` | add / remove the daily schedule (regenerated from `config.json`) |
| `./digest.sh disable` / `enable` | pause / resume without removing |
| `./digest.sh status` | installed? loaded? sent today? + tail of the last run log |
| `./digest.sh run` | run the full routine now |
| `./digest.sh capture` | capture today's PDF only and open it — check the selector |
| `./digest.sh send-test [number]` | send the latest PDF to a number (default your VA) — tune the WhatsApp steps fast |
| `./digest.sh logs` | tail today's run log |

**How often will you actually tweak it? Rarely:**

- The **capture selector** is set once and only needs revisiting if the web app gets
  redesigned. Adjust it in `config.json` and check with `./digest.sh capture`.
- The **WhatsApp steps** only need attention if a WhatsApp update moves the UI — and
  when that happens you'll get the failure notification + screenshot, then fix it in a
  tight loop: tweak `whatsapp.delaySeconds` / `whatsapp.sendMethod` in `config.json`
  (or the AppleScript in `scripts/send-whatsapp.sh`) and re-test with
  `./digest.sh send-test` until it lands. No rebuild needed for those.
- Changing **when** it runs is just `schedule.hour`/`minute` in `config.json` →
  `./digest.sh install` again.

## Troubleshooting

- **`dist/capture.js not found`** → `npm run build`.
- **`node: command not found` under launchd** → `run.sh` adds Homebrew/`nvm` paths; if
  Node is elsewhere, add its dir to the `export PATH=...` line.
- **Capture can't find today** → re-run `npm run find-today`; verify `today.dateFormat`
  matches the page exactly (locale, abbreviations).
- **Blank failure screenshot** → grant **Screen Recording**.
- **Nothing happens at the scheduled time** → check `logs/launchd.err.log`; confirm the
  plist paths are absolute and correct; confirm the Mac was awake & unlocked.
- **It sent, but you want to re-run today** → delete `state/sent-YYYY-MM-DD.flag`.

---

## What this does NOT do

- It doesn't log in for you — you sign in once into the persistent profile.
- It doesn't verify WhatsApp actually delivered the message (it can't read that
  reliably); it confirms the *script* ran. Spot-check the first few days.
- It's WhatsApp-version-sensitive by nature; if a WhatsApp update moves the UI, the
  send step may need re-tuning (you'll get the failure alert).
