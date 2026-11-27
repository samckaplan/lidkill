#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
pid=
cleanup() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT

export LIDKILL_FAKE_LID="$tmp/lid" LIDKILL_LOG="$tmp/log" LIDKILL_CONFIG="$tmp/config"
export LIDKILL_DRYRUN=1

lid() {
    printf '%s\n' "$1" >"$tmp/new-lid"
    mv "$tmp/new-lid" "$LIDKILL_FAKE_LID"
}

config() {
    printf 'MODE=%s\nDELAY=%s\n' "$1" "$2" >"$tmp/new-config"
    mv "$tmp/new-config" "$LIDKILL_CONFIG"
}

await_log() {
    local tries matches
    for ((tries = 0; tries < 100; tries++)); do
        matches=$(grep -Fc -- "$1" "$LIDKILL_LOG" 2>/dev/null || true)
        if [ "${matches:-0}" -ge "${2:-1}" ]; then
            return
        fi
        sleep 0.1
    done
    printf 'Missing log entry: %s\n' "$1" >&2
    cat "$LIDKILL_LOG" >&2
    return 1
}

await_pending() {
    local tries
    for ((tries = 0; tries < 30; tries++)); do
        [ -s "$tmp/pending" ] && return
        sleep 0.1
    done
    echo "Missing pending countdown" >&2
    return 1
}

lid closed
config poweroff 3
/bin/bash ./watcher.sh &
pid=$!
await_log "lid=closed mode=poweroff delay=3s dryrun=1 source=poll"
sleep 1.2
if grep -Fq 'lid closed' "$LIDKILL_LOG"; then
    echo "Watcher reacted to an already-closed lid" >&2
    exit 1
fi

lid open
sleep 1.2
lid closed
await_log "lid closed"
lid open
await_log "lid no longer confirmed closed - aborted"

lid closed
await_log "lid closed" 2
config reboot 3
await_log "DRY RUN: would execute /sbin/shutdown -r now"
sleep 1.2
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 1 ]

lid open
sleep 1.2
config poweroff 000
lid closed
await_log "DRY RUN: would execute /sbin/shutdown -h now"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 2 ]

lid open
sleep 1.2
config reboot 3
lid closed
await_pending
rm "$tmp/pending"
await_log "pending action cancelled"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 2 ]

lid open
sleep 1.2
config hard-restart 1
lid closed
await_log "DRY RUN: would execute /sbin/reboot -q"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 3 ]

kill "$pid"
wait "$pid"
pid=
: >"$LIDKILL_LOG"
lid open
config reboot 1
printf '%s\n' https://example.com/ >"$tmp/page-url"
/bin/bash ./watcher.sh &
pid=$!
await_log "lid=open mode=hard delay=25s dryrun=1 source=poll"

# Shorten the page countdown for the reopen and manual cancel checks.
printf '\nPAGE_DELAY=3\n' >>"$LIDKILL_CONFIG"
lid closed
await_log "lid closed"
await_pending
[ "$(sed -n '2p' "$tmp/pending")" = page ]
lid open
await_log "DRY RUN: would execute /sbin/halt -q"

lid closed
await_log "lid closed" 2
await_pending
rm "$tmp/pending"
lid open
await_log "pending action cancelled"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 1 ]

touch "$tmp/skip-next"
lid closed
await_log "skipped one lid close"
[ ! -e "$tmp/skip-next" ] && [ ! -e "$tmp/pending" ]
lid open
sleep 1.2

printf 'PAGE_CANCEL_ON_REOPEN=1\n' >>"$LIDKILL_CONFIG"
lid closed
await_pending
lid open
await_log "lid no longer confirmed closed - aborted"
[ ! -e "$tmp/pending" ]
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 1 ]


# ---- conditions, hook, arm timer (standard profile) ----
kill "$pid"
wait "$pid" || true
pid=
rm -f "$tmp/page-url" "$tmp/pending" "$tmp/skip-next"
export LIDKILL_NO_NOTIFY=1

restart() {  # restart <extra env...>: fresh watcher, fresh log, lid open
    if [ -n "$pid" ]; then kill "$pid"; wait "$pid" || true; pid=; fi
    : >"$LIDKILL_LOG"
    lid open
    env "$@" /bin/bash ./watcher.sh &
    pid=$!
}

printf 'MODE=poweroff\nDELAY=0\nWHEN_POWER=battery\n' >"$tmp/new-config"; mv "$tmp/new-config" "$LIDKILL_CONFIG"
restart LIDKILL_FAKE_POWER=ac
await_log "when=battery"
lid closed
await_log "ignored lid close: on ac power, rule is battery only"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 0 ]
lid open
restart LIDKILL_FAKE_POWER=battery
await_log "when=battery"
lid closed
await_log "DRY RUN: would execute /sbin/shutdown -h now"

printf 'MODE=poweroff\nDELAY=0\nIGNORE_EXTERNAL=1\n' >"$tmp/new-config"; mv "$tmp/new-config" "$LIDKILL_CONFIG"
restart LIDKILL_FAKE_DISPLAYS=1
await_log "ignore_external=1"
lid closed
await_log "ignored lid close: external display connected"
[ "$(grep -c 'DRY RUN: would execute' "$LIDKILL_LOG")" -eq 0 ]
lid open
restart LIDKILL_FAKE_DISPLAYS=0
await_log "ignore_external=1"
lid closed
await_log "DRY RUN: would execute /sbin/shutdown -h now"

# Hook: dry run only logs it; with the test switch it really runs, and is stopped at its time limit.
printf '#!/bin/bash\necho "hook ran in $LIDKILL_MODE" >"%s/hook-ran"\n' "$tmp" >"$tmp/hook.sh"
printf '#!/bin/bash\nsleep 30\n' >"$tmp/slow-hook.sh"
chmod +x "$tmp/hook.sh" "$tmp/slow-hook.sh"
printf 'MODE=reboot\nDELAY=0\nHOOK=%s\n' "$tmp/hook.sh" >"$tmp/new-config"; mv "$tmp/new-config" "$LIDKILL_CONFIG"
restart
await_log "lid=open"
lid closed
await_log "DRY RUN: would run hook $tmp/hook.sh"
await_log "DRY RUN: would execute /sbin/shutdown -r now"
[ ! -e "$tmp/hook-ran" ]
restart LIDKILL_TEST_HOOK=1
await_log "lid=open"
lid closed
await_log "hook exit status 0"
[ "$(cat "$tmp/hook-ran")" = "hook ran in reboot" ]
printf 'MODE=reboot\nDELAY=0\nHOOK=%s\nHOOK_TIMEOUT=1\n' "$tmp/slow-hook.sh" >"$tmp/new-config"; mv "$tmp/new-config" "$LIDKILL_CONFIG"
restart LIDKILL_TEST_HOOK=1
await_log "lid=open"
lid closed
await_log "hook timed out after 1s"
await_log "DRY RUN: would execute /sbin/shutdown -r now"

# Arm timer: an expired timer disarms (a dry run only logs it) and clears itself.
printf 'MODE=poweroff\nDELAY=0\n' >"$tmp/new-config"; mv "$tmp/new-config" "$LIDKILL_CONFIG"
printf '%s\n' "$(($(date +%s) + 2))" >"$tmp/arm-until"
restart
await_log "arm timer expired"
await_log "DRY RUN: would disarm"
[ ! -e "$tmp/arm-until" ]
# The watcher keeps working after a dry-run expiry.
lid closed
await_log "DRY RUN: would execute /sbin/shutdown -h now"

echo "Watcher dry-run checks passed"
