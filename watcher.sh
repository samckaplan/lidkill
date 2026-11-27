#!/bin/bash
# lidkill watcher - handles lid events and runs the configured power command.
# Do not run this by hand unless you mean it; use `lidkill test` for a dry run.

set -u

LABEL=com.lidkill.watcher
CFG="${LIDKILL_CONFIG:-$HOME/.config/lidkill/config}"
LOG="${LIDKILL_LOG:-$HOME/Library/Logs/lidkill.log}"
case "$CFG" in
    */*) CONFIG_DIR="${CFG%/*}" ;;
    *)   CONFIG_DIR=. ;;
esac
PENDING="$CONFIG_DIR/pending"
SKIP="$CONFIG_DIR/skip-next"
PAGE_URL="$CONFIG_DIR/page-url"
ARM_UNTIL="$CONFIG_DIR/arm-until"
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
skip_reason=

read_cfg() {
    local default_delay=1
    MODE=poweroff
    DELAY=1
    PAGE_MODE=hard
    PAGE_DELAY=25
    PAGE_CANCEL_ON_REOPEN=0
    DRYRUN=0
    WHEN_POWER=any
    IGNORE_EXTERNAL=0
    NOTIFY=0
    HOOK=
    HOOK_TIMEOUT=5
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
    case "$WHEN_POWER" in any|battery|ac) ;; *) WHEN_POWER=any ;; esac
    case "$HOOK_TIMEOUT" in [1-9]|[12][0-9]|30) ;; *) HOOK_TIMEOUT=5 ;; esac
}

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >>"$LOG" 2>/dev/null
}

# Desktop notification with a sound; never blocks the countdown.
notify() {
    [ "$NOTIFY" = 1 ] && [ -z "${LIDKILL_NO_NOTIFY:-}" ] || return 0
    /usr/bin/osascript -e "display notification \"$1\" with title \"Lidkill\" sound name \"Basso\"" \
        >/dev/null 2>&1 &
}

power_source() {
    local raw=${LIDKILL_FAKE_POWER:-}
    [ -n "$raw" ] || raw=$(/usr/bin/pmset -g batt 2>/dev/null | /usr/bin/head -n 1)
    case "$raw" in
        *"AC Power"*|ac)           echo ac ;;
        *"Battery Power"*|battery) echo battery ;;
        *)                         echo unknown ;;
    esac
}

external_count() {
    if [ -n "${LIDKILL_FAKE_DISPLAYS:-}" ]; then echo "$LIDKILL_FAKE_DISPLAYS"; return; fi
    [ -x "$MONITOR" ] || { echo 0; return; }
    "$MONITOR" --displays 2>/dev/null || echo 0
}

# Sets skip_reason when the configured conditions say not to act.
check_conditions() {
    local src
    skip_reason=
    if [ "$WHEN_POWER" != any ]; then
        src=$(power_source)
        if [ "$src" != unknown ] && [ "$src" != "$WHEN_POWER" ]; then
            skip_reason="on $src power, rule is $WHEN_POWER only"
            return
        fi
    fi
    if [ "$IGNORE_EXTERNAL" = 1 ] && [ "$(external_count)" -gt 0 ] 2>/dev/null; then
        skip_reason="external display connected"
    fi
}

# Runs the optional user hook (output goes to the log) with a time limit.
run_hook() {
    [ -n "$HOOK" ] || return 0
    if [ "$DRYRUN" = 1 ] && [ -z "${LIDKILL_TEST_HOOK:-}" ]; then
        log "DRY RUN: would run hook $HOOK"
        return 0
    fi
    if [ ! -x "$HOOK" ]; then
        log "hook $HOOK is not executable - skipped"
        return 0
    fi
    local hook_pid waited=0 limit=$((HOOK_TIMEOUT * 10))
    LIDKILL_MODE=$MODE "$HOOK" >>"$LOG" 2>&1 </dev/null &
    hook_pid=$!
    while kill -0 "$hook_pid" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            kill "$hook_pid" 2>/dev/null
            log "hook timed out after ${HOOK_TIMEOUT}s"
            return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    wait "$hook_pid"
    log "hook exit status $?"
}

# Seconds left on the arm timer; prints nothing when no timer is set.
timer_left() {
    local until now
    [ -s "$ARM_UNTIL" ] && IFS= read -r until <"$ARM_UNTIL" || return 0
    case "$until" in ''|*[!0-9]*) return 0 ;; esac
    now=$(/bin/date +%s)
    echo $((until - now))
}

# Timer ran out: restore normal sleep and unload ourselves. The sudoers rule
# written by `lidkill on` allows exactly this pmset call without a prompt.
disarm_expired() {
    log "arm timer expired"
    /bin/rm -f "$ARM_UNTIL"
    if [ "$DRYRUN" = 1 ]; then
        log "DRY RUN: would disarm"
        return 0
    fi
    if ! /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 >>"$LOG" 2>&1; then
        log "could not restore sleep without a password - staying armed (run: lidkill off)"
        return 0
    fi
    log "disarmed: normal lid sleep restored"
    notify "Arm timer ended. Lid close sleeps normally again."
    sleep 1
    /bin/launchctl disable "gui/$(id -u)/$LABEL" >/dev/null 2>&1
    /bin/launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
    exit 0
}

# Reads the next lid state from fd 3 into $current, enforcing the arm timer.
next_event() {
    local left deadline
    if [ ! -s "$ARM_UNTIL" ]; then
        IFS= read -r current <&3
        return
    fi
    while :; do
        left=$(timer_left)
        if [ -z "$left" ]; then IFS= read -r current <&3; return; fi
        if [ "$left" -le 0 ]; then disarm_expired; continue; fi
        deadline=$((SECONDS + left))
        if IFS= read -r -t "$left" current <&3; then return 0; fi
        # macOS Bash returns 1 for both EOF and timeout.
        [ "$SECONDS" -ge "$deadline" ] || return 1
    done
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

    run_hook

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
    log "watcher start pid=$$ lid=$previous mode=$MODE delay=${DELAY}s dryrun=$DRYRUN source=$1 when=$WHEN_POWER ignore_external=$IGNORE_EXTERNAL"
    while next_event; do
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
        check_conditions
        if [ -n "$skip_reason" ]; then
            log "ignored lid close: $skip_reason"
            previous=closed
            continue
        fi
        cancel_on_reopen=1
        if [ "$profile" = page ] && [ "$PAGE_CANCEL_ON_REOPEN" != 1 ]; then cancel_on_reopen=0; fi
        log "lid closed"
        if [ "$DELAY" -gt 0 ]; then
            if ! start_countdown; then
                log "could not publish countdown - aborted"
                previous=closed
                continue
            fi
            notify "Lid action ($MODE) in ${DELAY}s. Use the Lidkill menu to cancel."
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
            check_conditions
            if [ -n "$skip_reason" ]; then
                clear_countdown
                log "lid action cancelled: $skip_reason"
            elif claim_countdown; then
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
