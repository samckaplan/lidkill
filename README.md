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

## Commands

| command | what it does |
|---|---|
| `lidkill install` | copy watcher, LaunchAgent and config into place |
| `lidkill on` | arm (sudo once to write a sudoers rule + disable sleep) |
| `lidkill off` | disarm and restore normal lid sleep |
| `lidkill status` | lid state, mode, watcher pid, `SleepDisabled`, last log lines |
| `lidkill mode poweroff` | clean power off (default) |
| `lidkill mode reboot` | clean reboot |
| `lidkill mode hard` | `halt -q` — ungraceful, cache still flushed |
| `lidkill mode nuke` | `halt -nq` — no flush at all, closest to pulling power |
| `lidkill delay 3` | lid must stay shut N seconds before firing (0–60) |
| `lidkill dryrun on` | log only, never kill — safe for testing |
| `lidkill test` | watch the lid for 20s in dry-run mode |
| `lidkill logs` | tail the log |
| `lidkill uninstall` | remove everything |

## Safe first test (recommended)

With nothing unsaved, prove it works before trusting it:

```bash
lidkill dryrun on
lidkill on
# close the lid for ~5 seconds, then open it
lidkill logs
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
   `watcher.sh`, which polls `AppleClamshellState` from the IORegistry once a
   second.

When the lid goes `No` → `Yes`, it waits `DELAY` seconds, re-checks that the lid
is still shut, then runs the configured command. A passwordless sudo rule
limited to exactly those four commands (`/etc/sudoers.d/lidkill`) lets it work
with no prompt at lid-close time.

Everything is per-user; nothing runs as root except the one-shot shutdown
command itself.

## Honest limitations

- **This is not a hardware power cut.** No software on Apple Silicon can
  replicate holding the power button, because that is handled below the OS.
  `halt -nq` is the closest: it stops the kernel without flushing the disk.
  Treat `poweroff`/`reboot` as the sane defaults.
- **`nuke` can corrupt the filesystem and loses unsaved work.** So can `hard`.
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

- **Fires immediately on `lidkill on`** — the lid was already closed. `on`
  refuses unless you pass `--force`.
- **Sleeps on lid close anyway** — `SleepDisabled` is not sticking (MDM, or
  the setting did not apply). Re-run `lidkill on`.
- **Nothing in the log** — the agent is not loaded; run `lidkill off` then
  `lidkill on`.
