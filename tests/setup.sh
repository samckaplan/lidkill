#!/bin/bash
# Run in a disposable macOS environment. The installer writes into this user's home.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(plutil -extract ProgramArguments.0 raw menu/com.lidkill.menubar.plist)" != /usr/bin/open ]; then
    echo "The sign-in agent must launch the app bundle through LaunchServices." >&2
    exit 1
fi

./lidkill install
installed="$HOME/.local/bin/lidkill"
app="$HOME/Library/Application Support/lidkill/Lidkill.app"
agent="$HOME/Library/LaunchAgents/com.lidkill.menubar.plist"
domain="gui/$(id -u)"
codesign --verify --strict "$app"
[ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" = true ]
[ "$(plutil -extract ProgramArguments.2 raw "$agent")" = "$app" ]
[ "$(plutil -extract RunAtLoad raw "$agent")" = true ]

if launchctl print "$domain" >/dev/null 2>&1; then
    launchctl print "$domain/com.lidkill.menubar" >/dev/null
    for ((tries = 0; tries < 40; tries++)); do
        if "$installed" doctor | grep -q '^Menu bar: running'; then break; fi
        sleep 0.25
    done
    report=$("$installed" doctor)
    printf '%s\n' "$report"
    grep -q '^Menu bar: running' <<<"$report"
    "$installed" login off
    ! launchctl print "$domain/com.lidkill.menubar" >/dev/null 2>&1 || exit 1
    "$installed" login on
    launchctl print "$domain/com.lidkill.menubar" >/dev/null
else
    echo 'No Aqua session on runner. Verified the signed bundle and deferred sign-in job.'
fi

! launchctl print "$domain/com.lidkill.watcher" >/dev/null 2>&1 || exit 1
