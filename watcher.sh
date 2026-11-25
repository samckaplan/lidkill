#!/bin/bash
# lidkill watcher - runs under launchd, polls the lid, and kills the machine.
# Do not run this by hand unless you mean it; use `lidkill test` for a dry run.

set -u

CFG="${LIDKILL_CONFIG:-$HOME/.config/lidkill/config}"
LOG="${LIDKILL_LOG:-$HOME/Library/Logs/lidkill.log}"

MODE=poweroff
DELAY=1
DRYRUN=0

read_cfg() {
    MODE=poweroff
    DELAY=1
    DRYRUN=0
    if [ -r "$CFG" ]; then
        # shellcheck disable=SC1090
        . "$CFG"
    fi
    [ -n "${LIDKILL_DRYRUN:-}" ] && DRYRUN="$LIDKILL_DRYRUN"
    case "$DELAY" in ''|*[!0-9]*) DELAY=1 ;; esac
}

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$LOG" 2>/dev/null
}

# open | closed | unknown
lid_state() {
    # Test hook: LIDKILL_FAKE_LID may be "open"/"closed" or a file holding one.
    if [ -n "${LIDKILL_FAKE_LID:-}" ]; then
        if [ -f "$LIDKILL_FAKE_LID" ]; then
            head -n 1 "$LIDKILL_FAKE_LID"
        else
            printf '%s\n' "$LIDKILL_FAKE_LID"
        fi
        return
    fi
    local raw
    raw=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 4 2>/dev/null \
        | /usr/bin/awk -F' = ' '/"AppleClamshellState"/ {gsub(/[^A-Za-z0-9]/, "", $2); print $2; exit}')
    case "$raw" in
        Yes|1) echo closed ;;
        No|0)  echo open ;;
        *)     echo unknown ;;
    esac
}

fire() {
    local -a cmd
    case "$MODE" in
        poweroff) cmd=(/sbin/shutdown -h now) ;;
        reboot)   cmd=(/sbin/shutdown -r now) ;;
        hard)     cmd=(/sbin/halt -q) ;;
        nuke)     cmd=(/sbin/halt -nq) ;;
        *) log "unknown MODE=$MODE - refusing to act"; return 1 ;;
    esac

    if [ "$DRYRUN" = 1 ]; then
        log "DRY RUN: would execute ${cmd[*]}"
        return 0
    fi

    log "EXEC ${cmd[*]}"
    /usr/bin/sudo -n "${cmd[@]}" >>"$LOG" 2>&1
    local rc=$?
    log "exit status $rc"
    if [ "$rc" -ne 0 ]; then
        sleep 2
        log "retry"
        /usr/bin/sudo -n "${cmd[@]}" >>"$LOG" 2>&1
        log "retry exit status $?"
    fi
}

read_cfg
prev=$(lid_state)
log "watcher start pid=$$ lid=$prev mode=$MODE delay=${DELAY}s dryrun=$DRYRUN"

tick=0
while :; do
    sleep 1
    tick=$((tick + 1))
    # Re-read settings roughly every 30s so `lidkill mode ...` applies without a restart.
    [ $((tick % 30)) -eq 0 ] && read_cfg

    cur=$(lid_state)
    if [ "$cur" = unknown ]; then
        prev=$cur
        continue
    fi

    if [ "$cur" = closed ] && [ "$prev" != closed ]; then
        log "lid closed"
        d=$DELAY
        while [ "$d" -gt 0 ]; do
            sleep 1
            d=$((d - 1))
        done
        if [ "$(lid_state)" = closed ]; then
            fire
            prev=closed
            continue
        fi
        log "lid reopened before delay elapsed - aborted"
    fi

    prev=$cur
done
