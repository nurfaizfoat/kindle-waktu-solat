#!/bin/sh
#
# prepare-ldsymlink.sh - apply the firmware 5.17+ ScreenSavers workaround.
#
# BACKGROUND
#   The classic linkss ScreenSavers hack is confirmed working on PW3 / 5.12.2
#   and reported BROKEN on 5.17+, where the fix that users needed was:
#       mntroot rw
#       ln -s /lib/ld-linux-armhf.so.3 /lib/ld-linux.so.3
#       mntroot ro
#   Firmware 5.16.2.1.1 is in the untested gap, so this script is provided to
#   be run ONLY if the MRPI install of the hack fails.
#
# SAFETY
#   - Idempotent only when /lib/ld-linux.so.3 already resolves to the intended
#     /lib/ld-linux-armhf.so.3. A dangling or wrong symlink is reported and
#     left untouched (non-zero exit), never silently treated as success.
#   - Refuses to create a dangling symlink if the target is missing.
#   - The rootfs is returned to read-only on EVERY exit path, including failure
#     and signals (the EXIT trap guarantees it). The writable flag is set BEFORE
#     mntroot rw so the trap always attempts a restore.
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
  restore_ro
  if [ "$RO_FAIL" = "1" ]; then
    exit 7
  fi
}
trap 'on_exit' EXIT
trap 'on_exit; exit 130' INT TERM HUP

log "=== prepare-ldsymlink start ==="

if [ ! -d /lib ]; then
  log "FAIL: /lib does not exist - unexpected rootfs; refusing to touch anything"
  exit 2
fi

# --- idempotency / repair check ---------------------------------------------
if [ -L "$LINK" ]; then
  _resolved=$(readlink "$LINK" 2>/dev/null)
  log "found symlink: $LINK -> ${_resolved:-?}"
  if [ "$_resolved" = "$TARGET" ] && [ -e "$LINK" ]; then
    log "OK: $LINK resolves to $TARGET - nothing to do"
    log "=== done (no changes) ==="
    exit 0
  fi
  log "WARNING: $LINK does not resolve to $TARGET (resolved='${_resolved:-?}')."
  log "Refusing to change it automatically and NOT treating this as success."
  log "Run 'Remove ld symlink (rollback)' first, then re-run this action."
  log "See README.md step 3 and step 6."
  exit 6
elif [ -e "$LINK" ]; then
  log "WARNING: $LINK exists but is NOT a symlink - refusing to change it."
  log "Inspect it manually before continuing. See README.md step 3 and step 6."
  exit 6
fi

if ! command -v mntroot >/dev/null 2>&1; then
  log "FAIL: mntroot not found - cannot remount the rootfs read-write"
  exit 2
fi

if [ ! -L "$TARGET" ] && [ ! -e "$TARGET" ]; then
  log "FAIL: target $TARGET does not exist - refusing to create a dangling symlink"
  exit 2
fi

# --- guarded rootfs write ---------------------------------------------------
log "opening rootfs read-write (mntroot rw)"
# Set the writable flag FIRST so the EXIT trap always attempts a restore, even
# if mntroot rw reports a failure after the remount may have succeeded.
RO_OPEN=1
if ! mntroot rw; then
  log "WARNING: mntroot rw returned non-zero - will still attempt restore via trap"
fi

log "creating symlink: $LINK -> $TARGET"
if ln -s "$TARGET" "$LINK"; then
  log "ln -s reported success"
else
  log "FAIL: ln -s returned non-zero"
  exit 4
fi

if [ -L "$LINK" ] && [ "$(readlink "$LINK" 2>/dev/null)" = "$TARGET" ]; then
  log "verified: $(ls -l "$LINK" 2>&1)"
else
  log "FAIL: symlink is not visible/correct after creation"
  exit 5
fi

# Close the write window explicitly (the EXIT trap is the backstop).
if ! restore_ro; then
  log "ERROR: rootfs is still read-write - reboot the device now."
  exit 7
fi

log "=== done (symlink installed) ==="
exit 0
