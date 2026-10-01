#!/bin/sh
# Always-on waktu-solat dashboard for a jailbroken Kindle PW3.
#
# Takes over the e-ink panel by stopping the stock framework (which otherwise
# repaints over the board), paints the board, and refreshes on a timer.
#
# HOW TO STOP IT
#   1. Press the power button - a lipc watcher catches the sleep event and the
#      dashboard steps aside, returning the normal Kindle UI.
#   2. Create the file /mnt/us/dashboard/stop over USB.
#   3. Tap "Stop Waktu Solat" in the library - only reachable when the
#      framework is up, i.e. for clearing strays.
#   4. Reboot. Nothing auto-starts this, so a reboot always restores normality.
#
# SAFETY
#   - The framework is stopped ONLY after the board has been fetched and
#     validated. If the network is down the device UI is left untouched.
#   - The teardown trap is installed BEFORE the framework is stopped, so there
#     is no window where a signal could strand the device with no UI.
#   - The screensaver setting is restored on the way out, so the device can
#     sleep again instead of staying awake until reboot.
#
# Log: /mnt/us/dashboard/dashboard.log

# --- board URL configuration ------------------------------------------------
# The board URL is NOT hard-coded. It is read from a user-editable file that is
# sourced as a POSIX sh fragment, so it can be changed over USB without editing
# this script:
#     /mnt/us/dashboard/board-url.conf
# The placeholder below is the fallback used when that file is missing or
# unreadable; it is checked and rejected further down.
BOARD_URL="https://example.com/waktu/board.php"
BOARD_URL_CONF="/mnt/us/dashboard/board-url.conf"
if [ -r "$BOARD_URL_CONF" ]; then
  . "$BOARD_URL_CONF"
fi
DIR="/mnt/us/dashboard"
IMG="$DIR/board.png"
TMP="$DIR/board.png.tmp"
LOG="$DIR/dashboard.log"
STOP="$DIR/stop"
PIDFILE="$DIR/dashboard.pid"
FRAMEWORK="/etc/init.d/framework"

INTERVAL=300   # seconds between refreshes (5 minutes)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# --- refuse to run unless /mnt/us is really mounted ------------------------
# In USB drive mode the partition is unmounted from the device, so writes would
# silently create a SHADOW directory on the root filesystem and the pidfile and
# stop flag would be meaningless. Bail out rather than mislead.
if ! grep -q ' /mnt/us ' /proc/mounts 2>/dev/null; then
  exit 1
fi

mkdir -p "$DIR"

# --- configuration check ----------------------------------------------------
# Refuse to fetch anything until the user has pointed BOARD_URL at their own
# board deployment. The placeholder is never a real host.
if [ -z "${BOARD_URL:-}" ] || [ "$BOARD_URL" = "https://example.com/waktu/board.php" ]; then
  log "ERROR: the board URL is not configured."
  log "Create $BOARD_URL_CONF with a BOARD_URL line, for example:"
  log "    BOARD_URL=\"https://your-host/path/board.php\""
  log "Template: kindle-device/board-url.conf.sample in the repository."
  log "Refusing to fetch until it is configured."
  exit 1
fi

# --- single-instance guard -------------------------------------------------
# The launcher is a tappable library item, so it is easy to tap twice, and an
# earlier build had NO guard at all - the device log showed two 5-minute loops
# running side by side for hours, doubling fetches and panel refreshes.
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  # Confirm the pid is alive AND is actually one of our loops. A stale pid can
  # be reused by an unrelated process, and trusting it blindly would refuse a
  # perfectly valid start.
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null \
     && grep -qa '/dashboard\.sh' "/proc/$OLD/cmdline" 2>/dev/null; then
    log "already running as pid $OLD - refusing to start a second instance"
    exit 0
  fi
  log "stale pidfile (pid '$OLD' dead or unrelated) - continuing"
fi

# An instance started before the pidfile existed cannot be seen above, so hunt
# for it by script path in /proc. The leading slash matters: it matches the
# real loop at /mnt/us/dashboard/dashboard.sh but NOT stop-dashboard.sh.
SELF=$$
for proc in /proc/[0-9]*; do
  pid=${proc#/proc/}
  [ "$pid" = "$SELF" ] && continue
  if grep -qa '/dashboard\.sh' "$proc/cmdline" 2>/dev/null; then
    log "terminating stale instance pid $pid"
    kill -TERM "$pid" 2>/dev/null
  fi
done

# Let a terminated instance run its teardown, which restarts the framework.
# This must finish BEFORE we stop the framework below, or that restart would
# race with our own stop.
sleep 3

echo $$ > "$PIDFILE"

# --- teardown --------------------------------------------------------------
# Installed BEFORE the framework is touched, so no signal can arrive while the
# UI is down and leave it down.
#
# It is idempotent AND it always ends by exiting. That matters: in POSIX sh a
# trap handler that merely RETURNS lets the script carry on running. A bare
# `trap cleanup TERM` therefore ran the cleanup and then kept painting - which
# is precisely how a stray instance survived a kill.
CLEANED=0
FRAMEWORK_STOPPED=0
POWER_WATCH_PID=""
ORIG_PREVENT=""

cleanup() {
  if [ "$CLEANED" = "1" ]; then
    return 0
  fi
  CLEANED=1

  if [ -n "$POWER_WATCH_PID" ]; then
    kill "$POWER_WATCH_PID" 2>/dev/null
  fi

  # Restore the screensaver setting we changed, or the device stays awake
  # until the next reboot.
  if [ -n "$ORIG_PREVENT" ]; then
    lipc-set-prop com.lab126.powerd preventScreenSaver "$ORIG_PREVENT" >/dev/null 2>&1
  fi

  if [ "$FRAMEWORK_STOPPED" = "1" ]; then
    log "restoring framework"
    "$FRAMEWORK" start >/dev/null 2>&1
  fi

  rm -f "$PIDFILE"
}

on_signal() {
  cleanup
  exit 0
}

trap cleanup EXIT
trap on_signal INT TERM HUP

# --- locate an executable fbink -------------------------------------------
# /mnt/us is vfat with 'showexec', which only grants +x to .exe/.com/.bat.
# 'fbink' has no extension, so it cannot run in place. Fall back to a copy on
# tmpfs, which is RAM and always executable.
FBINK=""
for c in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink /usr/bin/fbink /usr/local/bin/fbink; do
  if [ -x "$c" ]; then
    FBINK="$c"
    break
  fi
done

if [ -z "$FBINK" ]; then
  for c in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink; do
    if [ -f "$c" ]; then
      cp "$c" /tmp/fbink 2>/dev/null
      chmod 755 /tmp/fbink 2>/dev/null
      if [ -x /tmp/fbink ]; then
        FBINK=/tmp/fbink
        break
      fi
    fi
  done
fi

if [ -z "$FBINK" ]; then
  log "FATAL: no executable fbink found - aborting, framework untouched"
  exit 1
fi

# --- fetch + validate -----------------------------------------------------
# Returns 0 only when $TMP holds something that really is a PNG.
fetch_board() {
  rm -f "$TMP"

  if command -v curl >/dev/null 2>&1; then
    curl -s -m 30 -o "$TMP" "$BOARD_URL" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP" "$BOARD_URL" || return 1
  else
    return 1
  fi

  [ -s "$TMP" ] || return 1

  SIG=$(dd if="$TMP" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
  [ "$SIG" = "89504e47" ] || return 1

  return 0
}

# --- preflight: prove we can reach the board BEFORE touching the UI -------
log "=== dashboard start (fbink=$FBINK, interval=${INTERVAL}s) ==="

if ! fetch_board; then
  log "ABORT: cannot reach the board (network down or server unreachable)."
  log "ABORT: Kindle UI deliberately left untouched."
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$IMG"
log "preflight OK: board fetched and validated"

# --- take over the panel --------------------------------------------------
# NOTE the ordering: the flag is set BEFORE the stop command. A POSIX trap is
# deferred until the current foreground command finishes, so a signal arriving
# during `framework stop` would otherwise reach cleanup with the flag still 0,
# skip the restart, and strand the device with no UI. Restarting an
# already-running framework is harmless, so erring this way costs nothing.
log "stopping framework"
FRAMEWORK_STOPPED=1
"$FRAMEWORK" stop >/dev/null 2>&1
sleep 4

# Did wifi survive? If not we would have no UI and no network. Exiting here
# lets the teardown trap restore the framework.
if ! fetch_board; then
  log "network lost after framework stop - aborting, teardown will restore the framework"
  rm -f "$TMP"
  exit 1
fi
log "network survived framework stop"

# Keep the screensaver off the panel, remembering what it was so teardown can
# put it back.
ORIG_PREVENT=$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)
case "$ORIG_PREVENT" in
  0|1) ;;
  *)   ORIG_PREVENT=0 ;;
esac

lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 \
  && log "screensaver suppressed (was $ORIG_PREVENT)" \
  || log "note: could not suppress screensaver"

# Clear any leftover stop flag BEFORE arming the watcher. The loop deliberately
# leaves the flag behind when it stops, so on a relaunch a stale flag would make
# the watcher's `while [ ! -f "$STOP" ]` false, exit it immediately, and leave
# the power button silently dead for the entire session.
rm -f "$STOP"

# --- power button: hand the screen back -----------------------------------
# Verified on THIS device by an on-device probe: /usr/bin/lipc-wait-event
# exists, and the powerd binary exposes exactly these event names. Any of them
# means the user is putting the device to sleep, so the dashboard steps aside.
#
# The wait is bounded by -s, and an event is distinguished from a plain timeout
# by how quickly the call returned. A bare unbounded wait would be cleaner but
# would leak a blocked process on every SIGKILL.
if command -v lipc-wait-event >/dev/null 2>&1; then
  (
    while [ ! -f "$STOP" ]; do
      T0=$(date +%s)
      lipc-wait-event -s 600 com.lab126.powerd \
        readyToSuspend,goingToScreenSaver,wakeupFromSuspend >/dev/null 2>&1
      T1=$(date +%s)
      ELAPSED=$((T1 - T0))

      # Returning well before the timeout means a real event fired; a full
      # timeout just means the device was idle, so re-arm rather than stopping
      # the board. Require ELAPSED >= 0 because a clock jump (RTC/NTP) can make
      # the delta negative, and treating that as an event would stop the
      # dashboard for no reason.
      if [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt 580 ]; then
        touch "$STOP"
        break
      fi

      if [ -f "$STOP" ]; then
        break
      fi
    done
  ) >/dev/null 2>&1 &
  POWER_WATCH_PID=$!

  # A watcher that dies instantly would fail silently - the exact trap this
  # whole feature is meant to avoid. Say so loudly in the log.
  sleep 1
  if kill -0 "$POWER_WATCH_PID" 2>/dev/null; then
    log "power-button watcher armed (pid $POWER_WATCH_PID)"
  else
    POWER_WATCH_PID=""
    log "WARNING: power-button watcher died at startup - power button will NOT stop the dashboard"
  fi
else
  log "note: lipc-wait-event missing - power button will not stop the dashboard"
fi

# --- loop -----------------------------------------------------------------
# Sleep in short slices rather than one long sleep, so a stop request is
# honoured within seconds instead of up to five minutes.
nap() {
  _nap_left=$1
  while [ "$_nap_left" -gt 0 ] && [ ! -f "$STOP" ]; do
    sleep 2
    _nap_left=$((_nap_left - 2))
  done
}

PAINTED=0

while [ ! -f "$STOP" ]; do
  if fetch_board; then
    mv "$TMP" "$IMG"
    "$FBINK" -g file="$IMG",halign=CENTER,valign=CENTER -W GC16
    RC=$?
    PAINTED=$((PAINTED + 1))
    log "painted #$PAINTED (fbink exit=$RC)"
    nap "$INTERVAL"
  else
    # Keep the previous image on screen; retry sooner than the full interval
    # but never in a tight loop.
    log "fetch failed - keeping current image, retrying in 60s"
    nap 60
  fi
done

# NOTE: the stop flag is deliberately NOT deleted here. If two instances are
# ever running, the first to notice would remove it and the second would carry
# on painting over whatever the user opened. It is cleared at the next start.
log "=== stop flag seen, shutting down dashboard ==="

exit 0
