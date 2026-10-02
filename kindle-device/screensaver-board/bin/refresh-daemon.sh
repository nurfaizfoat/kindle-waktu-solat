#!/bin/sh
#
# refresh-daemon.sh - long-lived board refresher for the Screensaver Board.
#
# WHAT IT DOES
#   Keeps the native screensaver board fresh without a manual tap. It refreshes:
#     - once shortly after it starts (SETTLE seconds);
#     - on every wake from sleep, debounced so a burst of wake events causes at
#       most one refresh per MIN_GAP seconds;
#     - at least once every INTERVAL seconds while the device stays awake.
#
#   The wait is sliced: instead of blocking for a full hour in lipc-wait-event,
#   each cycle waits at most SLICE seconds. That keeps the loop responsive to
#   signals (INT/TERM/HUP) and lets it re-check the /mnt/us mount each cycle.
#   A wake event is distinguished from a plain timeout by how quickly the wait
#   returned, and a clock jump (RTC/NTP) is detected by a negative elapsed time.
#   If lipc-wait-event returns suspiciously fast several times in a row it is
#   treated as broken and the process falls back to the sleep-based timer.
#   While the device is ASLEEP no process can run, so the board shown on wake or
#   on sleep is as fresh as the last refresh before sleep. This daemon only
#   refreshes while awake.
#
# WHY RETRIES
#   Wi-Fi often needs a few seconds to settle after a wake, so the first fetch
#   can fail transiently. refresh.sh preserves the previous board on failure, and
#   this daemon retries up to MAX_ATTEMPTS times, RETRY_DELAY apart, before
#   giving up for that cycle. A refresh.sh exit of 8 (board URL not configured)
#   is permanent and is not retried.
#
# SAFETY
#   - If /mnt/us is not mounted it waits MOUNT_WAIT seconds and retries instead
#     of exiting, so an upstart respawn can never burn its budget while the
#     userstore is unmounted (USB drive mode).
#   - Waits are interruptible within ~1s (nap loops on `sleep 1`), and refresh.sh
#     runs as a background child, so INT/TERM/HUP run cleanup promptly instead of
#     being deferred behind a long sleep or a 300s refresh. A deferred signal
#     could outlive the upstart job's `kill timeout 30` and be SIGKILLed,
#     skipping cleanup.
#   - Single-instance lock directory (with a live-PID AND cmdline check), so a
#     stale lock does not block a new start.
#   - Never stops or touches the framework; it only calls refresh.sh.
#   - A failed refresh keeps the previous board (refresh.sh guarantees this).
#   - Logs are rotated to <file>.1 once they exceed LOG_MAX bytes.
#   - Writes only under /mnt/us/dashboard and whatever refresh.sh itself writes.
#
# Log: /mnt/us/dashboard/refresh-daemon.log
#
# Usage: refresh-daemon.sh [-h]
#   -h   print this usage summary and exit 0 (no device writes)

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/refresh-daemon.log"
SSLOG="$DIR/screensaver.log"
PID="$DIR/refresh-daemon.pid"
LOCKDIR="$DIR/refresh-daemon.lock"
BIN=$(cd "$(dirname "$0")" && pwd)

INTERVAL=3600
SLICE=10
MAX_ATTEMPTS=3
RETRY_DELAY=20
SETTLE=10
MIN_GAP=60
MOUNT_WAIT=60
LOG_MAX=262144
REFRESH_PID=""

if [ "${1:-}" = "-h" ]; then
  echo "refresh-daemon.sh - refresh the screensaver board on wake and at least hourly."
  echo "Cadence: sliced ${SLICE}s wait, refresh on wake (${MIN_GAP}s debounce), ${INTERVAL}s floor."
  echo "Log: $LOG"
  exit 0
fi

# --- helpers ----------------------------------------------------------------
is_mounted() {
  awk '$2=="/mnt/us"{f=1} END{exit !f}' /proc/mounts 2>/dev/null
}

# nap <seconds>: sleep in 1s slices so a trapped signal is honored within ~1s
# instead of being deferred until a long sleep finally finishes.
nap() {
  _nap_left="$1"
  while [ "$_nap_left" -gt 0 ]; do
    sleep 1
    _nap_left=$((_nap_left - 1))
  done
}

log() {
  _ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$_ts $*"
  if [ -d "$DIR" ]; then
    echo "$_ts $*" >> "$LOG"
  fi
}

# rotate_log <file>: move a log over LOG_MAX bytes to <file>.1 (overwriting an
# old .1). Quiet when the file is missing or its size is unreadable.
rotate_log() {
  _rf="$1"
  [ -f "$_rf" ] || return 0
  _rsz=$(wc -c < "$_rf" 2>/dev/null)
  case "$_rsz" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$_rsz" -gt "$LOG_MAX" ]; then
    if mv -f "$_rf" "$_rf.1" 2>/dev/null; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') rotated $_rf (was ${_rsz} bytes) -> $_rf.1" >> "$LOG"
    fi
  fi
}

# --- /mnt/us must be a real mount; wait (do not exit) if it is not ----------
# Exiting here would make upstart respawn us in a tight loop while the userstore
# is unmounted (USB drive mode), burning the respawn budget for nothing. Install
# a minimal trap first so this wait is interruptible; it is replaced by the full
# cleanup trap once the lock is held.
trap 'exit 130' INT TERM HUP
while ! is_mounted; do
  echo "ERROR: /mnt/us is not mounted - waiting ${MOUNT_WAIT}s before retrying." >&2
  nap "$MOUNT_WAIT"
done

mkdir -p "$DIR" 2>/dev/null

# --- single instance --------------------------------------------------------
# A lock is only trusted when its PID is alive AND its cmdline still names
# refresh-daemon.sh, so a recycled PID cannot masquerade as the daemon.
pid_is_daemon() {
  _p="$1"
  [ -n "$_p" ] || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  grep -qa 'refresh-daemon\.sh' "/proc/$_p/cmdline" 2>/dev/null
}

acquire_lock() {
  _try=1
  while [ "$_try" -le 2 ]; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo $$ > "$LOCKDIR/pid" 2>/dev/null
      echo $$ > "$PID" 2>/dev/null
      return 0
    fi
    _oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null)
    if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null && pid_is_daemon "$_oldpid"; then
      log "REFUSING: refresh-daemon is already running (pid $_oldpid)."
      return 1
    fi
    log "stale lock found (pid ${_oldpid:-unknown}); removing it and retrying"
    rm -rf "$LOCKDIR" 2>/dev/null
    _try=$((_try + 1))
  done
  log "REFUSING: could not acquire lock $LOCKDIR."
  return 1
}

cleanup() {
  if [ -n "${REFRESH_PID:-}" ]; then
    kill "$REFRESH_PID" 2>/dev/null
  fi
  rm -f "$PID" 2>/dev/null
  rm -rf "$LOCKDIR" 2>/dev/null
}

if ! acquire_lock; then
  exit 9
fi
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT TERM HUP

# Run refresh.sh as a background child so a trapped TERM/HUP can kill it and let
# cleanup run promptly (a foreground child would defer the trap until it exits).
# Returns refresh.sh's exit code; resets REFRESH_PID before returning.
run_refresh() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 300 sh "$BIN/refresh.sh" &
  else
    sh "$BIN/refresh.sh" &
  fi
  REFRESH_PID=$!
  wait "$REFRESH_PID"
  _rc=$?
  REFRESH_PID=""
  return "$_rc"
}

# --- one refresh cycle, with retries ----------------------------------------
# Returns 0 on success, 1 on failure. It never aborts the caller's loop:
# refresh.sh keeps the previous board on failure.
refresh_once() {
  _attempt=1
  while [ "$_attempt" -le "$MAX_ATTEMPTS" ]; do
    log "refresh attempt $_attempt/$MAX_ATTEMPTS"
    run_refresh
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
      log "refresh attempt $_attempt succeeded"
      return 0
    fi
    if [ "$_rc" -eq 8 ]; then
      log "PERMANENT: the board URL is not configured (exit 8) - not retrying this cycle."
      return 1
    fi
    log "refresh attempt $_attempt failed (exit $_rc)"
    if [ "$_attempt" -lt "$MAX_ATTEMPTS" ]; then
      log "waiting ${RETRY_DELAY}s before the next attempt (wifi may still be settling)"
      nap "$RETRY_DELAY"
    fi
    _attempt=$((_attempt + 1))
  done
  log "FAIL: refresh failed after $MAX_ATTEMPTS attempts - keeping the previous board."
  return 1
}

# --- startup ----------------------------------------------------------------
log "=== refresh-daemon start (pid $$, interval ${INTERVAL}s, slice ${SLICE}s) ==="
rotate_log "$LOG"
rotate_log "$SSLOG"
log "settling ${SETTLE}s before the first refresh"
nap "$SETTLE"
refresh_once
last=$(date +%s)

# --- main loop --------------------------------------------------------------
HAVE_LIPC=1
if ! command -v lipc-wait-event >/dev/null 2>&1; then
  HAVE_LIPC=0
  log "WARNING: lipc-wait-event not found - using the sleep-based hourly timer only."
fi

FAST_RETURNS=0

while :; do
  if ! is_mounted; then
    echo "ERROR: /mnt/us became unmounted - waiting ${MOUNT_WAIT}s before retrying." >&2
    nap "$MOUNT_WAIT"
    continue
  fi

  rotate_log "$LOG"
  rotate_log "$SSLOG"

  _t0=$(date +%s)
  if [ "$HAVE_LIPC" = "1" ]; then
    lipc-wait-event -s "$SLICE" com.lab126.powerd wakeupFromSuspend >/dev/null 2>&1
  else
    sleep "$SLICE"
  fi
  _t1=$(date +%s)
  _elapsed=$((_t1 - _t0))

  # A wake event returned well before the slice timeout; a full timeout (or a
  # negative delta from a clock jump) is treated as a plain tick.
  WAKE=0
  if [ "$HAVE_LIPC" = "1" ] && [ "$_elapsed" -ge 0 ] && [ "$_elapsed" -lt $((SLICE - 2)) ]; then
    WAKE=1
  fi

  # Broken-lipc guard: a wait returning in under 2s repeatedly is not a real
  # wake event (or it is being fired in a loop). After 4 in a row, stop using
  # the event wait for this process and fall back to the hourly timer.
  if [ "$HAVE_LIPC" = "1" ] && [ "$_elapsed" -lt 2 ]; then
    FAST_RETURNS=$((FAST_RETURNS + 1))
    if [ "$FAST_RETURNS" -ge 4 ]; then
      log "WARNING: lipc-wait-event returned too fast 4 times - disabling event waits."
      HAVE_LIPC=0
      FAST_RETURNS=0
    fi
  else
    FAST_RETURNS=0
  fi

  now=$(date +%s)
  since=$((now - last))

  DO=0
  if [ "$last" = "0" ] || [ "$since" -lt 0 ]; then
    DO=1
  elif [ "$WAKE" = "1" ]; then
    [ "$since" -ge "$MIN_GAP" ] && DO=1
  else
    [ "$since" -ge "$INTERVAL" ] && DO=1
  fi

  if [ "$DO" = "1" ]; then
    if [ "$WAKE" = "1" ]; then
      log "wake event - refreshing (last refresh ${since}s ago)"
    else
      log "interval elapsed - refreshing (last refresh ${since}s ago)"
    fi
    refresh_once
    last=$(date +%s)
  fi
done
