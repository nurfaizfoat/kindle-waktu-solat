#!/bin/sh
#
# install-refresh-autostart.sh - install and start the refresh-daemon upstart job.
#
# WHAT IT DOES
#   Writes /etc/init/screensaver-board-refresh.conf so the refresh daemon starts
#   at boot, then reloads upstart and starts the job now. The daemon refreshes the
#   board on every wake from sleep and at least hourly while awake.
#
#   The job is started on the framework upstart job when one is present:
#   /etc/init/framework.conf -> "framework", else /etc/init/lab126_gui.conf ->
#   "lab126_gui". If neither exists the job falls back to
#   "start on runlevel [2345]" with no stop line, and a WARNING is logged.
#
# SAFETY
#   - Refuses to run if /mnt/us is not a mounted filesystem (log destination).
#   - Requires /mnt/us/extensions/screensaver-board/bin/refresh-daemon.sh.
#   - Refuses if mntroot is missing.
#   - The rootfs is returned to read-only on EVERY exit path, including failure
#     and signals (the EXIT trap guarantees it). The writable flag is set BEFORE
#     mntroot rw so the trap always attempts a restore.
#   - After mntroot ro the mount state is verified via /proc/mounts; if it is
#     still read-write after retries the script exits non-zero telling the user
#     to reboot.
#   - Idempotent: a byte-identical job file is not rewritten; the job is only
#     (re)started.
#   - The only rootfs write is the guarded mntroot rw/ro block below.
#
# Log: /mnt/us/dashboard/screensaver.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver.log"
JOBNAME=screensaver-board-refresh
JOBFILE=/etc/init/$JOBNAME.conf
DAEMON=/mnt/us/extensions/screensaver-board/bin/refresh-daemon.sh
TMPJOB="/tmp/${JOBNAME}.conf.$$"
JOBTMP=""

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
# rootfs_state parses /proc/mounts and prints "ro" or "rw" for the root mount.
rootfs_state() {
  _opts=$(awk '$2=="/"{print $4; exit}' /proc/mounts 2>/dev/null)
  case ",$_opts," in
    *,rw,*) echo rw ;;
    *) echo ro ;;
  esac
}

# RO_OPEN tracks whether rootfs read-write may be open, so the trap always
# attempts a restore once mntroot rw has been issued.
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
  rm -f "$TMPJOB" "$JOBTMP" 2>/dev/null
  restore_ro
  if [ "$RO_FAIL" = "1" ]; then
    exit 7
  fi
}
trap 'on_exit' EXIT
trap 'on_exit; exit 130' INT TERM HUP

log "=== install-refresh-autostart start ==="
log "mount guard OK: /mnt/us is mounted"

# --- prerequisites ----------------------------------------------------------
if [ ! -f "$DAEMON" ]; then
  log "FAIL: refresh daemon not found: $DAEMON"
  log "Copy extensions/screensaver-board onto the device and tap SS Board 6 again."
  exit 2
fi

if ! command -v mntroot >/dev/null 2>&1; then
  log "FAIL: mntroot not found - cannot remount the rootfs read-write"
  exit 2
fi

# --- detect the framework upstart job ---------------------------------------
FRAMEWORK_JOB=""
if [ -f /etc/init/framework.conf ]; then
  FRAMEWORK_JOB="framework"
elif [ -f /etc/init/lab126_gui.conf ]; then
  FRAMEWORK_JOB="lab126_gui"
else
  log "WARNING: no /etc/init/framework.conf or /etc/init/lab126_gui.conf found."
  log "WARNING: falling back to 'start on runlevel [2345]' with no stop line."
fi

if [ -n "$FRAMEWORK_JOB" ]; then
  START_LINE="start on started $FRAMEWORK_JOB"
  STOP_LINE="stop on stopping $FRAMEWORK_JOB"
  log "framework upstart job detected: $FRAMEWORK_JOB"
else
  START_LINE="start on runlevel [2345]"
  STOP_LINE=""
fi

# --- build the intended job content in /tmp for the idempotency check -------
emit_job_content() {
  echo "# Installed by screensaver-board: refreshes the board on wake and at least hourly."
  echo "# Managed by bin/install-refresh-autostart.sh; roll back with bin/remove-refresh-autostart.sh."
  echo "$START_LINE"
  if [ -n "$STOP_LINE" ]; then echo "$STOP_LINE"; fi
  echo "respawn"
  echo "respawn limit 10 300"
  echo "kill timeout 30"
  echo "exec /bin/sh $DAEMON"
}

emit_job_content > "$TMPJOB" 2>/dev/null

if [ ! -s "$TMPJOB" ]; then
  log "FAIL: could not build the intended job content"
  exit 2
fi

start_job() {
  if command -v initctl >/dev/null 2>&1; then
    initctl reload-configuration 2>/dev/null
    log "initctl reload-configuration done"
    if initctl start "$JOBNAME" 2>/dev/null; then
      log "started job $JOBNAME via initctl"
    elif command -v start >/dev/null 2>&1 && start "$JOBNAME" 2>/dev/null; then
      log "started job $JOBNAME via start"
    else
      log "WARNING: could not start $JOBNAME now; the job will start on the next boot"
    fi
  else
    log "initctl not present - the job will start on the next boot (reboot required now)"
  fi
}

# --- idempotency: byte-identical job file needs no rewrite ------------------
if [ -f "$JOBFILE" ] && cmp -s "$TMPJOB" "$JOBFILE"; then
  log "job file already up to date (byte-identical); not rewriting: $JOBFILE"
  start_job
  log "=== done (no changes) ==="
  exit 0
fi

# --- guarded rootfs write ---------------------------------------------------
log "opening rootfs read-write (mntroot rw)"
# Set the writable flag FIRST so the EXIT trap always attempts a restore, even
# if mntroot rw reports a failure after the remount may have succeeded.
RO_OPEN=1
if ! mntroot rw; then
  log "WARNING: mntroot rw returned non-zero - will still attempt restore via trap"
fi

log "writing upstart job atomically: $JOBFILE"
# Stage inside /etc/init (same filesystem as $JOBFILE), then rename, so a partial
# write can never leave a half-written job file that upstart might try to read.
JOBTMP="$JOBFILE.tmp.$$"
if ! emit_job_content > "$JOBTMP" 2>/dev/null; then
  log "FAIL: could not stage the job file at $JOBTMP"
  rm -f "$JOBTMP" 2>/dev/null
  exit 4
fi
if [ ! -s "$JOBTMP" ]; then
  log "FAIL: staged job file is empty: $JOBTMP"
  rm -f "$JOBTMP" 2>/dev/null
  exit 4
fi
if mv -f "$JOBTMP" "$JOBFILE"; then
  rm -f "$TMPJOB" 2>/dev/null
  log "job file written atomically"
else
  log "FAIL: could not rename $JOBTMP onto $JOBFILE"
  rm -f "$JOBTMP" 2>/dev/null
  exit 4
fi

if [ -s "$JOBFILE" ] && [ -r "$JOBFILE" ]; then
  log "verified: $JOBFILE is readable and non-empty"
else
  log "FAIL: $JOBFILE is missing, empty, or unreadable after write"
  exit 5
fi

# Close the write window explicitly (the EXIT trap is the backstop).
if ! restore_ro; then
  log "ERROR: rootfs is still read-write - reboot the device now."
  exit 7
fi

# --- start the job ----------------------------------------------------------
start_job

log "=== done (auto-refresh installed) ==="
exit 0
