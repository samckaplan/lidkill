# lidkill

Lidkill gives Mac laptops a configurable action when you close the lid.
Install on an Apple silicon or Intel Mac running macOS 12 or later.

## Install or update

Open Terminal while signed in to the Mac desktop. Install Xcode or run
`xcode-select --install` and finish the Apple installer if the tools are missing.

```bash
git clone https://github.com/samckaplan/lidkill.git
cd lidkill
./lidkill install
```

If you already cloned Lidkill, run `git pull --ff-only` and `./lidkill install`
inside your existing clone. Setup needs no administrator password. Fresh
installs start disarmed. Existing config is kept. If upgrading while armed,
re-arm the watcher to pick up the update. Double-clicking `install.command`
in Finder also runs setup.

### Copy-paste prompt for an AI agent

> Install or update Lidkill on this Mac from `https://github.com/samckaplan/lidkill`.
> Use the existing clone if available. Otherwise clone the official repo.
> Check for macOS 12+ and Apple Command Line Tools. If the tools are missing,
> ask me to finish the Apple installation before retrying. Run `./lidkill install`
> as my signed-in desktop user without sudo, then run `~/.local/bin/lidkill doctor`.
> Verify the menu app is running and launch at sign-in is enabled. If the app is
> stopped, run `~/.local/bin/lidkill menu` and check again. If macOS blocks the
> sign-in job, report the Login Items setting I need to approve. Keep a fresh
> install disarmed and preserve any existing settings. Do not close the lid,
> change power settings, request my password, or reboot during setup. Point me
> to **Lid Page → Set Website** for configuring the site from the menu bar.

## Menu bar

Lidkill opens immediately after setup and silently at each sign-in by default.
It stays in the background and the sign-in job relaunches it if it exits. The
menu icon takes one slot and shows seconds during a countdown. Use **Launch at
Sign-In** to control automatic launch and relaunch.

Click the icon to arm or disarm, select any lid action, set a preset or custom
delay, toggle dry run, or open the watcher log. Arming and disarming open
Terminal for the administrator prompt. **Setup Status** reports whether the
app, sign-in job, and lid watcher are running. **Copy Report** copies those
details for troubleshooting.

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
| `lidkill install` | copy watcher, LaunchAgent and config into place |
| `lidkill on` | arm (sudo once to write a sudoers rule + disable sleep) |
| `lidkill off` | disarm and restore normal lid sleep |
| `lidkill status` | lid state, mode, watcher pid, available detector, `SleepDisabled`, last log lines |
| `lidkill mode poweroff` | clean power off (default) |
| `lidkill mode reboot` | clean reboot |
| `lidkill mode hard` | `halt -q` — ungraceful, cache still flushed |
| `lidkill mode hard-restart` | `reboot -q` — ungraceful restart, cache still flushed |
| `lidkill mode nuke` | `halt -nq` — no flush at all, closest to pulling power |
| `lidkill delay 3` | lid must stay shut N seconds before firing (0–60) |
| `lidkill dryrun on` | log only, never kill — safe for testing |
| `lidkill test [seconds]` | watch the lid in dry-run mode for 1–300 seconds (default 20) |
| `lidkill menu` | open the macOS menu bar app |
| `lidkill doctor` | report menu startup and watcher status |
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
lidkill on
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

In standard mode, the watcher waits for the selected delay and verifies that
the lid is still shut before running the command. Reopening the lid during
that delay cancels the action. By default, Lid Page keeps counting after a reopen so you
can interact with the page on the built-in display. Mode and dry-run changes
are read before the action. Delay changes apply on the next close. A
passwordless sudo rule limited to the listed power commands
(`/etc/sudoers.d/lidkill`) lets it work with no prompt at lid-close time.

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

```bash
~/.local/bin/lidkill doctor
~/.local/bin/lidkill status
```

- **Menu icon missing** — run `~/.local/bin/lidkill menu`. Check the right side
  of the menu bar and any menu bar manager you use. If sign-in launch is blocked,
  check **System Settings → General → Login Items & Extensions** (macOS 13 or
  later) and allow the Lidkill background item, then run `~/.local/bin/lidkill login on`.
- **Arming with the lid closed** — `on` refuses unless you pass `--force`.
  After forcing, open the lid and close it again to trigger the watcher.
- **Detector shows polling** — install with Xcode or the Command Line Tools
  available to enable IOKit events. The watcher's start log reports the
  backend in use with `source=iokit` or `source=poll`.
- **Sleeps on lid close anyway** — `SleepDisabled` is not sticking (MDM, or
  the setting did not apply). Re-run `lidkill on`.
- **Nothing in the log** — the agent is not loaded; run `lidkill off` then
  `lidkill on`.
