#!/bin/sh
#
# remove-refresh-autostart.sh - roll back the refresh-daemon upstart job.
#
# WHAT IT DOES
#   Stops the upstart job screensaver-board-refresh FIRST (so it cannot respawn),
#   then stops the running refresh-daemon (best effort, only when the pidfile's
#   PID is alive AND its cmdline still names refresh-daemon.sh), and finally
#   removes /etc/init/screensaver-board-refresh.conf inside a guarded
#   mntroot rw/ro block. If the job file does not exist it is a no-op and prints
#   "nothing to do".
#
# SAFETY
#   - Refuses to run if /mnt/us is not a mounted filesystem (log destination).
#   - Idempotent: safe to run when nothing was installed.
#   - The writable flag is set BEFORE mntroot rw so the EXIT trap always attempts
#     a restore.
#   - After mntroot ro the mount state is verified via /proc/mounts; if it is
#     still read-write after retries the script exits non-zero telling the user
#     to reboot.
#   - The only rootfs write is the guarded mntroot rw/ro block below.
#
# Log: /mnt/us/dashboard/screensaver.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver.log"
JOBNAME=screensaver-board-refresh
JOBFILE=/etc/init/$JOBNAME.conf
PIDFILE=/mnt/us/dashboard/refresh-daemon.pid

# --- /mnt/us must be a real mount, or we would fabricate a dead dashboard dir
if ! awk '$2=="/mnt/us"{f=1} END{exit !f}' /proc/mounts 2>/dev/null; then
  echo "ERROR: /mnt/us is not a mounted filesystem - cannot write the log at $DIR." >&2
  echo "Mount the Kindle userstore and try again." >&2
  exit 10
fi

mkdir -p "$DIR" 2>/dev/null

log() {
  _ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$_ts $*"
  echo "$_ts $*" >> "$LOG"
}

# --- rootfs read-only guard -------------------------------------------------
rootfs_state() {
  _opts=$(awk '$2=="/"{print $4; exit}' /proc/mounts 2>/dev/null)
  case ",$_opts," in
    *,rw,*) echo rw ;;
    *) echo ro ;;
  esac
}

RO_OPEN=0
RO_FAIL=0
restore_ro() {
  if [ "$RO_OPEN" = "1" ]; then
    log "restoring rootfs to read-only (mntroot ro)"
    _try=0
    while [ "$_try" -lt 3 ]; do
      if mntroot ro; then break; fi
      _try=$((_try + 1))
      log "WARNING: mntroot ro attempt $_try failed"
      sleep 1
    done
    _state=$(rootfs_state)
    log "observed rootfs mount state: $_state"
    if [ "$_state" = "rw" ]; then
      log "ERROR: rootfs is STILL read-write after mntroot ro - REBOOT the device."
      RO_FAIL=1
      return 1
    fi
    RO_OPEN=0
  fi
  return 0
}

EXITING=0
on_exit() {
  [ "$EXITING" = "1" ] && return
  EXITING=1
  restore_ro
  if [ "$RO_FAIL" = "1" ]; then
    exit 7
  fi
}
trap 'on_exit' EXIT
trap 'on_exit; exit 130' INT TERM HUP

log "=== remove-refresh-autostart start ==="

# --- best-effort stop the upstart job FIRST ---------------------------------
# Stopping the job first means upstart will not respawn the daemon while we are
# still tearing things down.
if command -v initctl >/dev/null 2>&1; then
  if initctl stop "$JOBNAME" 2>/dev/null; then
    log "stopped job $JOBNAME via initctl"
  else
    log "initctl stop $JOBNAME returned non-zero (job may not be running)"
  fi
elif command -v stop >/dev/null 2>&1; then
  if stop "$JOBNAME" 2>/dev/null; then
    log "stopped job $JOBNAME via stop"
  else
    log "stop $JOBNAME returned non-zero (job may not be running)"
  fi
fi

# --- best-effort stop the daemon --------------------------------------------
if [ -f "$PIDFILE" ]; then
  _oldpid=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null \
     && grep -qa 'refresh-daemon\.sh' "/proc/$_oldpid/cmdline" 2>/dev/null; then
    log "stopping refresh-daemon (pid $_oldpid)"
    kill -TERM "$_oldpid" 2>/dev/null
  else
    log "no live refresh-daemon found in pidfile (pid ${_oldpid:-unknown})"
  fi
else
  log "no refresh-daemon pidfile present"
fi

# --- nothing to remove? -----------------------------------------------------
if [ ! -e "$JOBFILE" ]; then
  log "job file $JOBFILE does not exist - nothing to do"
  log "=== done (no changes) ==="
  exit 0
fi

if ! command -v mntroot >/dev/null 2>&1; then
  log "FAIL: mntroot not found - cannot remount the rootfs read-write"
  exit 2
fi

# --- guarded rootfs write ---------------------------------------------------
log "opening rootfs read-write (mntroot rw)"
RO_OPEN=1
if ! mntroot rw; then
  log "WARNING: mntroot rw returned non-zero - will still attempt restore via trap"
fi

log "removing job file: $JOBFILE"
if rm -f "$JOBFILE"; then
  log "rm reported success"
else
  log "FAIL: rm returned non-zero"
  exit 4
fi

if [ -e "$JOBFILE" ]; then
  log "FAIL: $JOBFILE is still present after removal"
  exit 5
fi

# Close the write window explicitly (the EXIT trap is the backstop).
if ! restore_ro; then
  log "ERROR: rootfs is still read-write - reboot the device now."
  exit 7
fi

# --- reload upstart ---------------------------------------------------------
if command -v initctl >/dev/null 2>&1; then
  initctl reload-configuration 2>/dev/null
  log "initctl reload-configuration done"
else
  log "initctl not present - no reload needed"
fi

log "=== done (auto-refresh removed) ==="
exit 0
