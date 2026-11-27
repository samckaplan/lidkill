# Lidkill — guide for AI agents (fix, troubleshoot, test)

You were sent here because Lidkill misbehaves on a Mac. Read this page top to bottom (3 minutes), do the **Fix it** steps, then **Report back**. You do not need to ask the user questions: everything below works without them, except the arm password (see Rules).

Lidkill = closing the Mac lid runs a power command. Menu bar app (Swift) + watcher (bash) + IOKit helper (C) + CLI `lidkill` (bash).

---

## 1. Rules (read first)

1. **Never close the lid, reboot, or shut down** while testing. Use dry run: `lidkill dryrun on`.
2. **Never run `lidkill on` yourself.** It needs the user's administrator password. If arming is needed, tell the user to run it in Terminal.
3. **Never use `mode nuke`** and never enter passwords, tokens or keys anywhere.
4. **Default behavior: once armed, closing the lid powers the Mac off** (`lidkill preset default` restores exactly that). You cannot arm (rule 2), so your install stays disarmed; tell the user to run `lidkill on` — or press Return at the "Arm now?" prompt when they run `./lidkill install` in Terminal. Do not leave a test install behind unless the user wants it (`lidkill uninstall` removes everything).
5. The app is **menu bar only**: no Dock icon, no controls window (the user rejected both). Do not re-add `statusItem.autosaveName` (PR #7 did and the icon vanished on one Mac).

---

## 2. Fix it (do these in order, stop when `doctor` is clean)

```bash
# 1. Get the latest code (clone location: wherever the user cloned it)
cd ~/lidkill 2>/dev/null || git clone https://github.com/samckaplan/lidkill.git ~/lidkill && cd ~/lidkill
git pull --ff-only

# 2. Install or update (no sudo). Needs macOS 12+ and Xcode or Command Line Tools.
./lidkill install

# 3. Diagnose
~/.local/bin/lidkill doctor

# 4. Repair what doctor flags (stops stray copies, trashes duplicate apps, clears saved menu position, rebuilds)
~/.local/bin/lidkill doctor --fix

# 5. Still wrong? Make the report (see section 5)
~/.local/bin/lidkill report
```

If `./lidkill install` says **Swift build tools are missing**: run `xcode-select --install`, tell the user to finish Apple's installer, then retry. Nothing else works without it.

---

## 3. Symptom → cause → fix

| You see | Cause | Fix |
|---|---|---|
| No menu bar icon | Notched Mac with a full menu bar: macOS hides icons that do not fit. `doctor` says `Menu icon: HIDDEN (behind the notch)`. Lidkill already deleted saved positions and re-added the icon twice (`repairs=`), so the bar itself is full. | Tell the user: hold ⌘ and drag unused icons off the bar (or switch items off in System Settings → Control Center / Menu Bar); the icon appears by itself. Everything also works via `lidkill config` and the CLI. The user does **not** want a Dock icon or a controls window: never add one. |
| No icon and `doctor` says `Menu icon: visible` | Menu bar manager (Bartender, Ice…) is hiding it | Reveal hidden items in that app. |
| Menu says **CLI Unavailable** | Another `Lidkill.app` (e.g. `/Applications/Lidkill.app`) is running and talks to a different CLI | `lidkill doctor --fix` (stops strays, moves duplicate apps to the Trash). |
| `doctor`: `Duplicate apps:` / `Stray Lidkill processes:` | Old copy of the app | `lidkill doctor --fix` |
| Icon is a solid square or blank | Artwork not converted to a template | Fixed in code (`MenuBar.makeGlyph`). Run `git pull --ff-only && ./lidkill install`. |
| `menu controls did not become ready` | App crashed or macOS blocked the sign-in job | `cat ~/Library/Logs/lidkill-menu.log`; check System Settings → General → Login Items & Extensions → allow **Lidkill**; then `lidkill login on`. |
| Menu app stopped | Crash or quit | `lidkill menu` |
| Lid close just sleeps the Mac (armed) | `SleepDisabled` is 0 (MDM, or arm never finished) | Ask the user to run `lidkill on` again in Terminal. `doctor` flags this. |
| Armed but nothing happens | Sudoers rule missing, or a setting ignores the close (dry-run, `when`, `external`, Lid Page, skip) | `lidkill status`; `lidkill logs 40`. Log line `ignored lid close: …` or `DRY RUN` names the setting. Reset everything to the factory behavior: `lidkill preset default`. |
| Closing the lid does nothing with a monitor attached | `external` is on (clamshell protection) | `lidkill external off` |
| Disarm asks for a password | Armed with a version older than 0.3 | Fine once: `lidkill off`, then re-arm to refresh the sudoers rule. |
| `sudoers missing` after uninstall | Uninstall had no password | Harmless. `sudo rm -f /etc/sudoers.d/lidkill` and `sudo pmset -a disablesleep 0` |
| Detector says `polling` | Helper not built (no Xcode tools at install) | Install the tools, then `./lidkill install --force` |

Useful checks (all safe, no password):

```bash
lidkill status        # armed? lid, power source, mode, conditions, timer, sudoers
lidkill config        # every setting with its meaning
lidkill logs 60       # watcher log
lidkill logs --follow # live
cat ~/.config/lidkill/menu-state   # icon visible/hidden + why + window frame + notch
```

---

## 4. Test it (no password, nothing shuts down)

Run from a clone of the repo. All of these use simulated lids or a temporary HOME.

```bash
bash tests/cli.sh        # settings, presets, report (temp HOME) ~2 s
bash tests/watcher.sh    # fake lid: delay, cancel, conditions, hook, arm timer ~45 s
xcrun swiftc -swift-version 5 menu/MenuBar.swift menu/LidPage.swift tests/menu.swift -o /tmp/lk-smoke
/tmp/lk-smoke                                              # menu items, icon rendering, menu request
LIDKILL_FAKE_HIDDEN=1 LIDKILL_EXPECT_FALLBACK=1 /tmp/lk-smoke  # hidden icon gets repositioned
```

`bash tests/setup.sh` installs for real into the current user's home — only on a disposable Mac, or follow it with `lidkill uninstall`.

End-to-end lid check **without** killing anything:

```bash
lidkill dryrun on
lidkill test 30      # watches 30 s in dry run; close and open the lid to see "DRY RUN: would execute …"
lidkill dryrun off
```

Test hooks (environment variables for the watcher): `LIDKILL_FAKE_LID`, `LIDKILL_FAKE_POWER=ac|battery`, `LIDKILL_FAKE_DISPLAYS=<n>`, `LIDKILL_NO_NOTIFY=1`, `LIDKILL_TEST_HOOK=1` (run the hook even in dry run), `LIDKILL_DRYRUN=1`, `LIDKILL_CONFIG`, `LIDKILL_LOG`. App: `LIDKILL_FAKE_HIDDEN=1`.

---

## 5. Report back (this is what the maintainer needs)

```bash
~/.local/bin/lidkill report
```

- Writes `~/Library/Logs/lidkill-report.txt` and **copies it to the clipboard**.
- Your user name and home folder are replaced by `<user>` and `~`. No passwords or keys are collected.
- Contains: macOS version, Mac model, notch yes/no, icon visible/hidden + reason, installed files, duplicate apps, launchd state, config, last 60 log lines, crash report head.

Then write to the user (or open an issue at <https://github.com/samckaplan/lidkill/issues/new?template=bug_report.md>):

```
Mac: <model>, macOS <version>
What I ran: <commands>
Result: <fixed | not fixed>
doctor says: <paste "Menu icon" and "Next steps" lines>
Report: <paste or attach lidkill-report.txt>
```

---

## 6. Where things live

| Thing | Path |
|---|---|
| CLI | `~/.local/bin/lidkill` (source: `lidkill` in the repo) |
| Installed files, app, helper | `~/Library/Application Support/lidkill/` |
| Config | `~/.config/lidkill/config` (also `pending`, `skip-next`, `arm-until`, `menu-ready`, `menu-state`, `source`) |
| Logs | `~/Library/Logs/lidkill.log` (watcher), `lidkill-menu.log` (sign-in job), `lidkill-report.txt` |
| LaunchAgents | `~/Library/LaunchAgents/com.lidkill.watcher.plist` (armed), `com.lidkill.menubar.plist` (menu app) |
| Root rule | `/etc/sudoers.d/lidkill` (power commands + `pmset -a disablesleep 0` only) |
| Menu bar app | `menu/MenuBar.swift` (menu, icon, notch probe, re-add repair), `menu/LidPage.swift`, `menu/MenuApp.swift`, `menu/build.sh` |
| Watcher | `watcher.sh` (events, conditions, hook, arm timer), `lid-events.c` (IOKit events, `--displays`) |

Settings: `mode`, `delay`, `dryrun`, `when` (any/battery/ac), `external`, `notify`, `hook`, plus `preset default|safe|desk|guard|battery` and `setup` (guided).

## 7. Known macOS facts (do not rediscover)

- On notched Macs, new menu bar icons are placed next to the notch and are the first to be hidden. Tested on a notched M3 Max (macOS 27.2): a plain command-line status item obeys `NSStatusItem Preferred Position <name>` (value 20 moves it to the far right), but the bundled Lidkill.app ignores any value (always x=1126), so Lidkill does not try to seed a slot. It saves nothing, deletes every `NSStatusItem*` default on launch, and re-adds the icon (twice per launch at most) when its window is behind the notch or off screen.
- `NSWindow.occlusionState` reads "hidden" while the display sleeps or is locked, so it is **not** used to decide icon visibility.
- Two apps with the same bundle id (`com.lidkill.menubar`) break the menu. Install stops stray copies; `doctor --fix` trashes duplicates.
- `screencapture` and window lists need Screen Recording permission; rely on `menu-state` instead.
- `CGImage.copy(maskingColorComponents:)` behaved differently across releases; the icon is now built by converting luminance to alpha.
- Arming needs `sudo`; disarming and the arm timer use a narrow sudoers rule so they need no password.
