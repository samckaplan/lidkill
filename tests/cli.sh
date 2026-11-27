#!/bin/bash
# Exercises the settings commands against a throwaway HOME. Touches no launchd jobs.
set -euo pipefail
cd "$(dirname "$0")/.."

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
export HOME="$home"
cfg="$home/.config/lidkill/config"
lk() { ./lidkill "$@"; }
want() { grep -qxF -- "$1" "$cfg" || { echo "config is missing: $1" >&2; cat "$cfg" >&2; exit 1; }; }

# "default" restores the factory behavior even after a test left dry-run on.
lk dryrun on >/dev/null; lk delay 9 >/dev/null; lk mode nuke >/dev/null 2>&1; touch "$home/.config/lidkill/skip-next"
lk preset default >/dev/null
want MODE=poweroff; want DELAY=1; want WHEN_POWER=any; want IGNORE_EXTERNAL=0; want NOTIFY=0; want DRYRUN=0
[ ! -e "$home/.config/lidkill/skip-next" ]
lk preset safe >/dev/null
want MODE=poweroff; want DELAY=5; want WHEN_POWER=any; want IGNORE_EXTERNAL=0; want NOTIFY=1
lk preset desk >/dev/null
want DELAY=3; want IGNORE_EXTERNAL=1
lk preset guard >/dev/null
want MODE=hard; want DELAY=0; want NOTIFY=0
lk preset battery >/dev/null
want WHEN_POWER=battery
! lk preset nonsense >/dev/null 2>&1

lk set mode reboot >/dev/null; want MODE=reboot
lk set delay 7 >/dev/null; want DELAY=7
lk when ac >/dev/null; want WHEN_POWER=ac
lk external on >/dev/null 2>&1; want IGNORE_EXTERNAL=1
lk notify off >/dev/null; want NOTIFY=0
! lk when sideways >/dev/null 2>&1
! lk delay 61 >/dev/null 2>&1
! lk set nothing x >/dev/null 2>&1

# Settings are rewritten in place, never duplicated, and values with spaces survive.
[ "$(grep -c '^DELAY=' "$cfg")" -eq 1 ]
mkdir "$home/my hooks"; printf '#!/bin/bash\n' >"$home/my hooks/a.sh"; chmod +x "$home/my hooks/a.sh"
lk hook "$home/my hooks/a.sh" >/dev/null
( . "$cfg"; [ "$HOOK" = "$home/my hooks/a.sh" ] )
! lk hook "$home/missing.sh" >/dev/null 2>&1
lk hook off >/dev/null
( . "$cfg"; [ -z "$HOOK" ] )

# menu-status keeps its old seven leading fields and appends the new ones.
status=$(lk menu-status)
[ "$(printf '%s\n' "$status" | wc -l | tr -d ' ')" -eq 11 ]
[ "$(printf '%s\n' "$status" | sed -n '8p')" = ac ]

# --for is validated before anything privileged happens.
! lk on --for forever >/dev/null 2>&1
! lk on --for 10s >/dev/null 2>&1

# The report works without an install, and never leaks the home folder.
report=$(lk report --stdout)
grep -q '^== lidkill report ==' <<<"$report"
! grep -qF "$home" <<<"$report"

grep -q 'when' <<<"$(lk config)"
grep -q '^lidkill ' <<<"$(lk version)"
echo "CLI checks passed"
