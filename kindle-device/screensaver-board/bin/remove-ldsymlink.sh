#!/bin/sh
#
# remove-ldsymlink.sh - roll back the firmware 5.17+ ScreenSavers workaround.
#
# WHAT IT DOES
#   Removes ONLY the symlink /lib/ld-linux.so.3 that prepare-ldsymlink.sh
#   creates. It never touches /lib/ld-linux-armhf.so.3 or any other rootfs file.
#   This gives the README's rootfs rollback an executable action instead of
#   SSH-only prose.
#
# SAFETY
#   - Refuses to run if /mnt/us is not a mounted filesystem (log destination).
#   - Refuses unless /lib/ld-linux.so.3 is a symlink resolving to
#     /lib/ld-linux-armhf.so.3, so it cannot delete a stock file or a foreign
#     symlink.
#   - The writable flag is set BEFORE mntroot rw so the EXIT trap always
#     attempts a restore.
#   - After mntroot ro the mount state is verified via /proc/mounts; if it is
#     still read-write after retries the script exits non-zero telling the user
#     to reboot.
#   - The only rootfs write is the guarded mntroot rw/ro block below.
#
# Log: /mnt/us/dashboard/screensaver.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver.log"
LINK=/lib/ld-linux.so.3
TARGET=/lib/ld-linux-armhf.so.3

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

log "=== remove-ldsymlink start ==="

if [ ! -d /lib ]; then
  log "FAIL: /lib does not exist - unexpected rootfs; refusing to touch anything"
  exit 2
fi

if [ ! -L "$LINK" ]; then
  if [ -e "$LINK" ]; then
    log "WARNING: $LINK exists but is NOT a symlink - refusing to delete it."
    exit 6
  fi
  log "OK: $LINK does not exist - nothing to remove"
  log "=== done (no changes) ==="
  exit 0
fi

_resolved=$(readlink "$LINK" 2>/dev/null)
log "found symlink: $LINK -> ${_resolved:-?}"
if [ "$_resolved" != "$TARGET" ]; then
  log "WARNING: $LINK does not point to $TARGET - refusing to remove it."
  log "This is not the workaround symlink this bundle creates. Inspect manually."
  exit 6
fi

if ! command -v mntroot >/dev/null 2>&1; then
  log "FAIL: mntroot not found - cannot remount the rootfs read-write"
  exit 2
fi

log "opening rootfs read-write (mntroot rw)"
# Set the writable flag FIRST so the EXIT trap always attempts a restore, even
# if mntroot rw reports a failure after the remount may have succeeded.
RO_OPEN=1
if ! mntroot rw; then
  log "WARNING: mntroot rw returned non-zero - will still attempt restore via trap"
fi

log "removing symlink: $LINK"
if rm -f "$LINK"; then
  log "rm reported success"
else
  log "FAIL: rm returned non-zero"
  exit 4
fi

if [ -L "$LINK" ] || [ -e "$LINK" ]; then
  log "FAIL: $LINK is still present after removal"
  exit 5
fi

if ! restore_ro; then
  log "ERROR: rootfs is still read-write - reboot the device now."
  exit 7
fi

log "=== done (symlink removed) ==="
exit 0
