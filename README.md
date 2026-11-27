# lidkill

Lidkill gives Mac laptops a configurable action when you close the lid.
Install on an Apple silicon or Intel Mac running macOS 12 or later.

**Something wrong on a Mac? Point your AI agent at [AGENTS.md](AGENTS.md)** — a short
fix / troubleshoot / test guide. Or run `lidkill doctor --fix`, then `lidkill report`.

## Install or update

Open Terminal while signed in to the Mac desktop. Install Xcode or run
`xcode-select --install` and finish the Apple installer if the tools are missing.

```bash
git clone https://github.com/samckaplan/lidkill.git
cd lidkill
./lidkill menu
```

Update later with `lidkill update` (or `git pull --ff-only && ./lidkill install`).
Setup itself needs no administrator password. **Default behavior: once armed,
closing the lid powers the Mac off** (clean shutdown after 1 second, always). When you
run the install in Terminal it ends by asking "Arm now?" (press Return; your password is
needed once). Installs run by scripts or agents have no terminal, so they stay disarmed.
Existing config is kept, and unchanged parts are not rebuilt. If upgrading while armed,
the install offers to re-arm so the update's sudoers rule applies. Double-clicking `install.command`
in Finder also runs setup.

### Copy-paste prompt for an AI agent

> Install, fix or update Lidkill on this Mac from `https://github.com/samckaplan/lidkill`.
> Clone the repo (or `git pull --ff-only` in the existing clone) and follow `AGENTS.md`
> exactly. Run `./lidkill install` as my signed-in desktop user without sudo, then
> `~/.local/bin/lidkill doctor` and, if it flags anything, `~/.local/bin/lidkill doctor --fix`.
> If it still fails, run `~/.local/bin/lidkill report` and give me its output.
> Keep the install disarmed (you have no terminal to arm it; I will answer the arm prompt
> myself). Do not close the lid, change power settings, request
> my password, or reboot. Do not ask me questions: `AGENTS.md` covers the decisions.

## Configure in one minute

Pick whichever is easiest. Every route edits the same settings.

```bash
lidkill setup               # answer five questions
lidkill preset desk         # or a one-step preset: default | safe | desk | guard | battery
lidkill config              # see every setting and what it means
lidkill set delay 5         # change one setting (same as: lidkill delay 5)
```

Or use the menu bar: **Presets**, **Lid Action**, **Delay**, **Only When**,
**Ignore With External Display**, **Notify Before Action**.

| preset | does |
|---|---|
| `default` | factory behavior: clean power off after 1 s, always. Also clears dry-run, the hook and a pending skip. Use it to get back to "closing the lid shuts down". |
| `safe` | clean power off after 5 s, with a notification |
| `desk` | clean power off after 3 s, **ignored while an external display is connected** (clamshell-safe) |
| `guard` | hard shutdown immediately, silent |
| `battery` | clean power off after 3 s, only on battery |

### Smart behavior

- **Only when** — `lidkill when battery` acts only on battery power (`ac` for the opposite, `any` for always).
- **External display** — `lidkill external on` ignores the lid while a monitor is connected, so closing the lid at a desk does not shut the Mac down.
- **Timed arm** — `lidkill on --for 2h` (30m, 1d, up to 7d). The watcher restores normal sleep and unloads itself when time is up. The menu has **Arm For** 1, 4 or 8 hours.
- **Notify** — `lidkill notify on` shows a notification with a sound when the countdown starts.
- **Hook** — `lidkill hook ~/bin/before-kill.sh` runs your script just before the action (5-second limit, output goes to the log, not run in dry run). It sees `LIDKILL_MODE`.
- **Passwordless disarm** — arming installs a narrow sudoers rule, so **Disarm** in the menu and the arm timer need no password.

## Menu bar

Lidkill opens immediately after setup and silently at each sign-in by default.
It stays in the background and the sign-in job relaunches it if it exits. The
menu icon takes one slot and shows seconds during a countdown. Use **Launch at
Sign-In** to control automatic launch and relaunch.

`./lidkill menu` installs or repairs the menu from the checkout if needed and
opens the icon's menu. There is no separate window: Lidkill lives only in the top menu bar.

Click the icon to arm or disarm, select any lid action, set a preset or custom
delay, toggle dry run, or open the watcher log. Arming opens Terminal for the
administrator prompt; disarming needs no password once armed. **Setup Status**
reports whether the app, icon, sign-in job, and lid watcher are healthy.
**Copy Diagnostic Report** puts a redacted report on the clipboard for a bug report.

**Icon hidden?** On a notched Mac with a full menu bar, macOS hides icons that do not
fit, newest first. Lidkill saves no icon position (a stale saved slot is one way an
icon vanishes), checks that the icon is really on screen, and adds it again if not.
If the bar is completely full, free space (⌘-drag unused icons off the bar) and it
appears by itself.

Choose **Preview Countdown** to try the icon countdown and Cancel without
arming. An armed watcher shows its countdown for delays above zero.
**Cancel Pending Action** skips that lid close. Open and close the lid
again to start a new countdown.
Use **Skip Next Lid Close** to ignore one future close while keeping Lidkill
armed. Click it again to clear the skip.

### Lid Page

Choose **Lid Page → Set Website** and enter an HTTP or HTTPS URL. **Preview Website**
opens the browser window safely before you arm Lidkill. The window has one
tab, a read-only address bar, and navigation within the configured site.
Additional tabs, pop-ups, off-site navigation, and downloads are blocked.
Sites that send you to a different domain for sign-in may fail to load.
**Test Countdown With Website** shows the real page, countdown, and cancel
control without touching the watcher or macOS power settings.

Once armed, closing the lid starts a **25-second countdown** and opens the
site. Reopening keeps the countdown going by default. Turn on **Lid Page →
Cancel on Reopen** to stop the countdown when the lid reopens. Choose **Cancel Lid Action**
in the window or **Cancel Pending Action** in the menu to stop it. An active
external display can show the window while the lid is physically shut.

Lid Page defaults to **Hard Shutdown**, which powers off the Mac. Choose
**Hard Restart** to boot back up after the countdown. **Lid Action** and
**Delay** apply to the currently selected setup. **Disable Lid Page** returns
to the standard lid settings. Use a delay above zero to show the website.

Hard Restart applies to the lid action. After a manual shutdown, startup
follows the Mac’s hardware and power settings. FileVault may require sign-in
before Lidkill can appear in the menu bar.

## Commands

| command | what it does |
|---|---|
| `lidkill install [--force]` | copy watcher, LaunchAgent and config into place; rebuilds only what changed |
| `lidkill setup` | guided configuration |
| `lidkill preset safe\|desk\|guard\|battery` | one-step settings |
| `lidkill config` / `lidkill set <name> <value>` | show / change settings |
| `lidkill on [--for 2h]` | arm (sudo once to write a sudoers rule + disable sleep); optional auto-disarm |
| `lidkill off` | disarm and restore normal lid sleep (no password if armed with 0.3+) |
| `lidkill status` | lid, power source, mode, conditions, timer, watcher pid, detector, `SleepDisabled`, last log lines |
| `lidkill mode poweroff` | clean power off (default) |
| `lidkill mode reboot` | clean reboot |
| `lidkill mode hard` | `halt -q` — ungraceful, cache still flushed |
| `lidkill mode hard-restart` | `reboot -q` — ungraceful restart, cache still flushed |
| `lidkill mode nuke` | `halt -nq` — no flush at all, closest to pulling power |
| `lidkill delay 3` | lid must stay shut N seconds before firing (0–60) |
| `lidkill dryrun on` | log only, never kill — safe for testing |
| `lidkill when any\|battery\|ac` | act only on this power source |
| `lidkill external on` | ignore lid close while an external display is connected |
| `lidkill notify on` | notification and sound when a countdown starts |
| `lidkill hook <script>` / `lidkill hook off` | run a script before the action |
| `lidkill test [seconds]` | watch the lid in dry-run mode for 1–300 seconds (default 20) |
| `lidkill menu` | open the macOS menu bar app |
| `lidkill doctor [--fix]` | report (and repair) menu app, icon, duplicates, sign-in job, watcher |
| `lidkill report` | write a redacted diagnostic report and copy it to the clipboard |
| `lidkill update` / `lidkill version` | pull and reinstall the latest version / print version |
| `lidkill login on` / `lidkill login off` | control automatic launch and relaunch |
| `lidkill cancel` | cancel a pending lid-close action |
| `lidkill skip on` / `lidkill skip off` | schedule or clear a one-time skip |
| `lidkill page-reopen on` / `lidkill page-reopen off` | toggle cancel on reopen for Lid Page |
| `lidkill logs [lines]` | show recent log entries (default 40) |
| `lidkill logs --follow` | watch new log entries as they arrive |
| `lidkill uninstall` | remove everything |

## Safe first test (recommended)

With nothing unsaved, prove it works before trusting it:

```bash
lidkill dryrun on
lidkill on --for 30m
lidkill test 30
# close the lid for ~5 seconds, then open it before the test ends
```

You should see `DRY RUN: would execute /sbin/shutdown -h now` and the Mac
should **not** power off. That proves both lid detection and `disablesleep`
are working on your machine. Then:

```bash
lidkill dryrun off
```

If the Mac simply sleeps when you close the lid, the watcher never gets to
run — see Troubleshooting.

## How it works

macOS sleeps the moment the lid closes, which would freeze any watcher before
it could react. So arming does two things:

1. `sudo pmset -a disablesleep 1` — the Mac stays awake with the lid shut
   (shown as `SleepDisabled 1` in `pmset -g`).
2. A LaunchAgent (`~/Library/LaunchAgents/com.lidkill.watcher.plist`) runs
   `watcher.sh`. With Xcode or the Command Line Tools available at install
   time, the watcher uses a local IOKit helper that waits for lid events
   without polling. If the helper is unavailable or exits, the watcher
   checks the IORegistry once a second.

Before acting the watcher checks the power-source and external-display
conditions (once at close and again after the delay), then runs the optional
hook, then the command. In standard mode, the watcher waits for the selected
delay and verifies that the lid is still shut before running the command. Reopening the lid during
that delay cancels the action. By default, Lid Page keeps counting after a reopen so you
can interact with the page on the built-in display. Mode and dry-run changes
are read before the action. Delay changes apply on the next close. A
passwordless sudo rule limited to the listed power commands and to
`pmset -a disablesleep 0` (`/etc/sudoers.d/lidkill`) lets it work with no prompt
at lid-close time and lets it restore sleep when an arm timer ends.

Everything is per-user; nothing runs as root except the one-shot shutdown
command itself.

## Honest limitations

- **This is not a hardware power cut.** No software on Apple Silicon can
  replicate holding the power button, because that is handled below the OS.
  `halt -nq` is the closest: it stops the kernel without flushing the disk.
  Treat `poweroff`/`reboot` as the sane defaults.
- **`nuke` can corrupt the filesystem and loses unsaved work.** Hard Shutdown
  and Hard Restart can also lose unsaved work.
- **While armed, the Mac never sleeps.** Closed in a bag it will keep running
  (and heating) until power-off. That is inherent to detecting the lid.
- **FileVault** means the next boot asks for your password; that is normal.
- If a plist/MDM policy blocks `pmset`, `lidkill status` will show
  `SleepDisabled 0` while armed and the Mac will simply sleep — the watcher
  cannot help then.

## Troubleshooting

Short version: `lidkill doctor --fix`, then `lidkill report` if it is still wrong.
AI agents: follow [AGENTS.md](AGENTS.md).

```bash
~/.local/bin/lidkill doctor        # health check with "Next steps"
~/.local/bin/lidkill doctor --fix  # stop stray apps, trash duplicates, reset icon position, rebuild
~/.local/bin/lidkill report        # redacted report for a bug report (copied to the clipboard)
```

- **Menu icon missing** — `doctor` says whether the icon is hidden and why. On a
  notched Mac the bar is full: ⌘-drag unused icons off it and Lidkill's icon
  appears by itself. If sign-in launch is blocked, check **System
  Settings → General → Login Items & Extensions** (macOS 13 or later), allow the
  Lidkill background item, then run `~/.local/bin/lidkill login on`.
- **"CLI Unavailable" in the menu** — usually a second `Lidkill.app` (for example
  in `/Applications`). `lidkill doctor --fix` removes the duplicate.
- **Arming with the lid closed** — `on` refuses unless you pass `--force`.
  After forcing, open the lid and close it again to trigger the watcher.
- **Lid close ignored** — a setting is doing it. The log says `ignored lid close:`
  with the reason (`lidkill config` shows `when` and `external`).
- **Detector shows polling** — install with Xcode or the Command Line Tools
  available to enable IOKit events. The watcher's start log reports the
  backend in use with `source=iokit` or `source=poll`.
- **Sleeps on lid close anyway** — `SleepDisabled` is not sticking (MDM, or
  the setting did not apply). Re-run `lidkill on`.
- **Nothing in the log** — the agent is not loaded; run `lidkill off` then
  `lidkill on`.

## Development

```bash
bash tests/cli.sh       # settings and report, temporary HOME
bash tests/watcher.sh   # simulated lid: delay, cancel, conditions, hook, arm timer
xcrun swiftc -swift-version 5 menu/MenuBar.swift menu/LidPage.swift tests/menu.swift -o /tmp/lk-smoke && /tmp/lk-smoke
```
