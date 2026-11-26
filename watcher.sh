#!/bin/bash
# lidkill watcher - handles lid events and runs the configured power command.
# Do not run this by hand unless you mean it; use `lidkill test` for a dry run.

set -u

CFG="${LIDKILL_CONFIG:-$HOME/.config/lidkill/config}"
LOG="${LIDKILL_LOG:-$HOME/Library/Logs/lidkill.log}"
case "$CFG" in
    */*) CONFIG_DIR="${CFG%/*}" ;;
    *)   CONFIG_DIR=. ;;
esac
PENDING="$CONFIG_DIR/pending"
SKIP="$CONFIG_DIR/skip-next"
PAGE_URL="$CONFIG_DIR/page-url"
[ "${LIDKILL_PREVIEW_ONLY:-0}" = 1 ] && PENDING=
countdown_live=0
SCRIPT="${BASH_SOURCE[0]}"
case "$SCRIPT" in
    */*) MONITOR="${SCRIPT%/*}/lid-events" ;;
    *)   MONITOR="./lid-events" ;;
esac

MODE=poweroff
DELAY=1
DRYRUN=0

read_cfg() {
    local default_delay=1
    MODE=poweroff
    DELAY=1
    PAGE_MODE=hard
    PAGE_DELAY=25
    PAGE_CANCEL_ON_REOPEN=0
    DRYRUN=0
    if [ -r "$CFG" ]; then
        # shellcheck disable=SC1090
        . "$CFG"
    fi
    PROFILE=${1:-standard}
    if [ "$#" -eq 0 ] && [ -s "$PAGE_URL" ]; then PROFILE=page; fi
    if [ "$PROFILE" = page ]; then
        MODE=$PAGE_MODE
        DELAY=$PAGE_DELAY
        default_delay=25
    fi
    [ -n "${LIDKILL_DRYRUN:-}" ] && DRYRUN="$LIDKILL_DRYRUN"
    [ -n "${LIDKILL_FAKE_LID:-}" ] && DRYRUN=1
    case "$DELAY" in ''|*[!0-9]*) DELAY=$default_delay ;; esac
    DELAY=${DELAY#"${DELAY%%[!0]*}"}
    DELAY=${DELAY:-0}
    case "$DELAY" in [0-9]|[1-5][0-9]|60) ;; *) DELAY=$default_delay ;; esac
}

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$LOG" 2>/dev/null
}

start_countdown() {
    [ -n "$PENDING" ] || return 0
    local temp now
    temp=$(/usr/bin/mktemp "${PENDING}.XXXXXX") || return 1
    if now=$(/bin/date +%s) && printf '%s\n' "$((now + DELAY))" >"$temp" &&
        { [ "$PROFILE" != page ] || printf '%s\n' page >>"$temp"; } &&
        /bin/mv -f "$temp" "$PENDING"; then
        countdown_live=1
        return 0
    fi
    /bin/rm -f "$temp"
    return 1
}

clear_countdown() {
    if [ "$countdown_live" = 1 ]; then
        /bin/rm -f "$PENDING"
        countdown_live=0
    fi
}

claim_countdown() {
    [ "$countdown_live" = 1 ] || return 0
    countdown_live=0
    # Cancel unlinks the same file. Rename wins only if the request still exists.
    /bin/mv -f "$PENDING" "$PENDING.firing.$$" 2>/dev/null || return 1
    /bin/rm -f "$PENDING.firing.$$"
}

# Sets state to open, closed, or unknown.
lid_state() {
    local line
    state=unknown
    # Test hook: LIDKILL_FAKE_LID may be "open"/"closed" or a file holding one.
    if [ -n "${LIDKILL_FAKE_LID:-}" ]; then
        line=$LIDKILL_FAKE_LID
        if [ -f "$LIDKILL_FAKE_LID" ]; then
            IFS= read -r line <"$LIDKILL_FAKE_LID" || true
        fi
        case "$line" in open|closed) state=$line ;; esac
        return
    fi

    while IFS= read -r line; do
        case "$line" in
            *'"AppleClamshellState" = Yes'|*'"AppleClamshellState" = 1') state=closed; break ;;
            *'"AppleClamshellState" = No'|*'"AppleClamshellState" = 0') state=open; break ;;
        esac
    done < <(/usr/sbin/ioreg -r -n IOPMrootDomain -d 1 2>/dev/null)
}

poll_lid() {
    local previous=
    while :; do
        lid_state
        if [ "$state" != "$previous" ]; then
            printf '%s\n' "$state" || return
            previous=$state
        fi
        sleep 1
    done
}

fire() {
    local mode=$MODE profile=$PROFILE cancel_on_reopen=$1 state
    local -a cmd
    case "$MODE" in
        poweroff)     cmd=(/sbin/shutdown -h now) ;;
        reboot)       cmd=(/sbin/shutdown -r now) ;;
        hard)         cmd=(/sbin/halt -q) ;;
        hard-restart) cmd=(/sbin/reboot -q) ;;
        nuke)         cmd=(/sbin/halt -nq) ;;
        *)            log "unknown MODE=$MODE - refusing to act"; return 1 ;;
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
        lid_state
        read_cfg "$profile"
        if { [ "$cancel_on_reopen" = 1 ] && [ "$state" != closed ]; } || [ "$DRYRUN" = 1 ] || [ "$MODE" != "$mode" ]; then
            log "retry cancelled: lid state or settings changed"
            return
        fi
        log "retry"
        /usr/bin/sudo -n "${cmd[@]}" >>"$LOG" 2>&1
        log "retry exit status $?"
    fi
}

watch_lid() {
    local previous current state deadline remaining profile cancel_on_reopen
    IFS= read -r -t 5 previous <&3 || return
    read_cfg
    log "watcher start pid=$$ lid=$previous mode=$MODE delay=${DELAY}s dryrun=$DRYRUN source=$1"
    while IFS= read -r current <&3; do
        if [ "$previous" != open ] || [ "$current" != closed ]; then
            previous=$current
            continue
        fi

        if [ -n "$PENDING" ] && [ -f "$SKIP" ] && /bin/rm "$SKIP" 2>/dev/null; then
            log "skipped one lid close"
            previous=closed
            continue
        fi
        read_cfg
        profile=$PROFILE
        cancel_on_reopen=1
        if [ "$profile" = page ] && [ "$PAGE_CANCEL_ON_REOPEN" != 1 ]; then cancel_on_reopen=0; fi
        log "lid closed"
        if [ "$DELAY" -gt 0 ]; then
            if ! start_countdown; then
                log "could not publish countdown - aborted"
                previous=closed
                continue
            fi
            deadline=$((SECONDS + DELAY))
            while remaining=$((deadline - SECONDS)); [ "$remaining" -gt 0 ]; do
                if IFS= read -r -t "$remaining" current <&3; then
                    previous=$current
                    if [ "$cancel_on_reopen" = 1 ]; then
                        clear_countdown
                        log "lid no longer confirmed closed - aborted"
                        continue 2
                    fi
                    if [ "$countdown_live" = 1 ] && [ ! -e "$PENDING" ]; then
                        clear_countdown
                        log "pending action cancelled"
                        continue 2
                    fi
                else
                    # macOS Bash returns 1 for both EOF and timeout.
                    [ "$SECONDS" -ge "$deadline" ] || return
                fi
            done
        fi
        kill -0 "$monitor_pid" 2>/dev/null || return
        lid_state
        if [ "$cancel_on_reopen" = 0 ] || [ "$state" = closed ]; then
            read_cfg "$profile"
            if claim_countdown; then
                fire "$cancel_on_reopen"
            else
                log "pending action cancelled"
            fi
        else
            clear_countdown
            log "lid no longer confirmed closed - aborted"
        fi
        previous=closed
        [ "$profile" != page ] || previous=$state
    done
}

monitor_pid=
stop_monitor() {
    clear_countdown
    if [ -n "$monitor_pid" ]; then
        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null
        monitor_pid=
    fi
}

trap stop_monitor EXIT
trap 'exit 0' HUP INT TERM

# launchd runs one watcher. Discard a countdown left by an unclean exit.
[ -z "$PENDING" ] || /bin/rm -f "$PENDING"

if [ -x "$MONITOR" ] && [ -z "${LIDKILL_FAKE_LID:-}" ]; then
    exec 3< <(exec "$MONITOR")
    monitor_pid=$!
    watch_lid iokit
    stop_monitor
    exec 3<&-
    log "lid event monitor unavailable - falling back to polling"
fi

exec 3< <(poll_lid)
monitor_pid=$!
watch_lid poll
