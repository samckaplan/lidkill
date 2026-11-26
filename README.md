# lidkill

Closing the lid powers the Mac off — or reboots it — instead of sleeping.
Toggleable on/off with one command.

```bash
cd ~/AgentWorkspace/documents/lidkill
./lidkill install      # no sudo, just copies files into your home
./lidkill on           # asks for your password once, then arms it
./lidkill off          # disarm, back to normal lid sleep
./lidkill status
```

After `install`, the command lives at `~/.local/bin/lidkill`. If that is not on
your `PATH`, the installer prints the one line to add.
On an armed installation, run `lidkill on` again after upgrading to restart
the watcher.

## Menu bar

On macOS 12 or later, install with Xcode or the Command Line Tools. Lidkill
opens in the menu bar at every sign-in without a Dock icon or startup window.
Use `lidkill menu` to open it again after quitting. If an older Lidkill menu
app is running during an upgrade, quit it and run `lidkill menu`.

Click the Lidkill icon to arm or disarm, set the action and delay, toggle dry
run, or open the watcher log. Arming and disarming open Terminal for the
administrator prompt.

Choose **Preview Countdown** to try the icon countdown and Cancel without
arming. An armed watcher shows its countdown for delays above zero.
**Cancel Pending Action** skips that lid close. Open and close the lid
again to start a new countdown.

### Lid Page

Choose **Lid Page → Set Website** and enter an HTTP or HTTPS URL. **Preview Website**
opens the browser window safely before you arm Lidkill. The window has one
tab, a read-only address bar, and navigation within the configured site.
Additional tabs, pop-ups, off-site navigation, and downloads are blocked.
Sites that send you to a different domain for sign-in may fail to load.

Once armed, closing the lid starts a **25-second countdown** and opens the
site. Reopening the lid keeps the countdown going. Choose **Cancel Lid Action**
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
| `lidkill cancel` | cancel a pending lid-close action |
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
that delay cancels the action. Lid Page keeps counting after a reopen so you
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
lidkill status
lidkill logs
launchctl print gui/$(id -u)/com.lidkill.watcher
pmset -g | grep SleepDisabled      # must be 1 while armed
```

- **Arming with the lid closed** — `on` refuses unless you pass `--force`.
  After forcing, open the lid and close it again to trigger the watcher.
- **Detector shows polling** — install with Xcode or the Command Line Tools
  available to enable IOKit events. The watcher's start log reports the
  backend in use with `source=iokit` or `source=poll`.
- **Sleeps on lid close anyway** — `SleepDisabled` is not sticking (MDM, or
  the setting did not apply). Re-run `lidkill on`.
- **Nothing in the log** — the agent is not loaded; run `lidkill off` then
  `lidkill on`.
