# Running this as a Claude Cowork routine (native WhatsApp app)

This is the "in Claude" version of the digest: a **Cowork scheduled routine** that
captures today's section and sends it through your **native WhatsApp Mac app**.

## Can Cowork really drive the native WhatsApp app? Yes — with caveats.

- ✅ **Native app works.** Cowork's **computer use runs directly on your real screen
  with no sandbox**, so it can click your actual WhatsApp Mac app window (not just
  WhatsApp Web).
- ⚠️ **Computer use is research-preview.** Anthropic recommends watching it act; it's
  not yet production-grade for unattended use.
- ⚠️ **Scheduled-task permission bug.** Scheduled Cowork tasks have been reported to
  re-prompt for permission every run and stall (claude-code issue #47180) — so a
  truly hands-off 6am run can hang waiting for approval.
- ❌ **Cowork can't run our `run.sh`.** Cowork's shell/code execution happens in an
  **isolated Linux VM** (Apple Virtualization.framework) with no access to macOS
  `osascript` or host apps. So the native-app send must go through Cowork's
  **computer use**, not the deterministic AppleScript in `scripts/send-whatsapp.sh`.
- ⚠️ **Only runs while the Mac is awake and Claude Desktop is open.** Your overnight
  `caffeinate` covers "awake"; just leave Claude Desktop open.

**Bottom line:** great as an **attended** morning routine (you around to approve /
glance). If you need **truly unattended + native + deterministic**, use the `launchd`
routine in this folder instead (see `README.md`).

### Sources
- Cowork desktop architecture — isolated Linux VM: <https://support.claude.com/en/articles/14479288-claude-cowork-desktop-architecture-overview>
- Computer use has no sandbox to your screen: <https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork>, <https://support.claude.com/en/articles/13364135-use-claude-cowork-safely>
- Scheduled tasks need Mac awake + Desktop open: <https://support.claude.com/en/articles/13854387-schedule-recurring-tasks-in-claude-cowork>
- Scheduled-task permission-prompt bug: claude-code issue #47180

## One-time setup

1. **Claude Desktop** installed and signed in (Pro or Max), with **Cowork** open.
2. Enable **computer use** in Cowork (Settings → it's a research-preview toggle).
3. **WhatsApp Mac app** installed, signed in, and the VA reachable by name or number.
4. Be **logged into the schedule page** in your default browser.
5. Keep the Mac awake overnight (e.g. `caffeinate`) and **leave Claude Desktop open**.

## The routine — paste into Cowork's `/schedule`

Set frequency = **Daily** at your time, then use this task (fill in the < > parts):

> Every morning, do the following on my Mac. If any step fails or looks wrong,
> stop and message me instead of guessing:
>
> 1. In my default browser, open <YOUR SCHEDULE URL>. I'm already logged in.
> 2. Find the section under **today's** date heading (today = the current calendar date).
> 3. Capture just that section and save it as a PDF named `today-<YYYY-MM-DD>.pdf`
>    in `~/Documents/task-digest/` (create the folder if it doesn't exist).
> 4. Open the **WhatsApp** desktop app and open the chat with <VA NAME or +NUMBER>.
> 5. Attach that PDF to the chat, add the caption "<YOUR CAPTION>", and send it.
> 6. Confirm to me that it sent, including the file name.

## First runs = supervised

Run the task **manually once** from Cowork. Approve each permission prompt (choose
"Always allow" where offered) and watch it complete. Re-run it manually a few mornings
until the steps are reliable on your machine. Only then lean on the schedule — and
still spot-check, given the research-preview status and the permission-prompt bug.

## Optional: a more reliable native send (advanced)

To avoid Cowork clicking through WhatsApp by vision, connect a **host-side AppleScript
MCP server** (e.g. `applescript-mcp`) to Cowork. Because an MCP server runs as a normal
host process **outside** the Linux VM, it *can* run `osascript` and drive the native app
deterministically — and you can point it at this folder's `scripts/send-whatsapp.sh`.
Cowork then orchestrates (find today's section, make the PDF) while the MCP server does
the dependable native-app send. Trade-off: extra setup, and the scheduled-task
permission caveat still applies.
