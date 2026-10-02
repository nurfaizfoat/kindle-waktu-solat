#!/bin/sh
#
# set-screensaver.sh - install a PNG as the ONE native Kindle screensaver.
#
# WHY THIS EXISTS
#   The linkss ScreenSavers hack reads custom images from
#   /mnt/us/linkss/screensavers/. Placing a single file named
#   bg_ss00.png there makes closing the lid show that image and opening the lid
#   return to reading - the native sleep path, with no framebuffer takeover and
#   no clock/battery chrome drawn over the board.
#
# WHY EXACTLY ONE FILE
#   With several bg_* files present, linkss cycles through them, which makes the
#   board appear on some sleeps and not others. This script ALWAYS installs the
#   final name bg_ss00.png, then MOVES every other *.png in the pool into
#   /mnt/us/dashboard/screensaver-quarantine (recoverable, never deleted), so the
#   pool ends with exactly one file.
#
# FINAL-FILE NAME (FW >= 5.5)
#   On firmware 5.5 and newer, linkss's shuffless names pool files
#   bg_ss00.png, bg_ss01.png, ... (its ss_prefix is "bg_ss" for K5_ATLEAST_55).
#   A legacy bg_<group>_ss00.png is only renamed to bg_ss00.png by shuffless at
#   boot, so writing it takes effect only after a reboot. To be read live at the
#   next sleep, the pool file must already carry the final name bg_ss00.png.
#   This script always targets bg_ss00.png directly and quarantines any extras.
#   linkss bind-mounts /mnt/us/linkss/screensavers onto
#   /usr/share/blanket/screensaver, so replacing the correctly-named file is
#   picked up at the next sleep without a framework restart.
#
# SAFETY
#   - Refuses to run if /mnt/us is not a mounted filesystem, and refuses if
#     /mnt/us/linkss does not exist (hack not installed): it never fabricates a
#     directory linkss would not read.
#   - Refuses a source PNG that is not exactly 1072x1448 (fail closed).
#   - Backs up an existing destination to <dest>.bak once before overwriting.
#   - Copies to a unique temp file and moves into place, so a partial copy can
#     never replace a good screensaver.
#   - A single-instance pidfile guards against two KUAL taps racing.
#   - Verifies the installed file exists, is non-empty, and has 1072x1448 IHDR.
#   - Writes only /mnt/us/dashboard (log + quarantine), and the linkss
#     screensaver pool.
#
# Usage: set-screensaver.sh [png-path]  (default /mnt/us/dashboard/board.png)
# Log:   /mnt/us/dashboard/screensaver.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver.log"
LINKS=/mnt/us/linkss
SSDIR=/mnt/us/linkss/screensavers
SRC="${1:-/mnt/us/dashboard/board.png}"
LOCK="$DIR/set-screensaver.lock"
QUARANTINE="$DIR/screensaver-quarantine"
BIN=$(cd "$(dirname "$0")" && pwd)

# --- /mnt/us must be a real mount, or we would fabricate a dead dashboard dir
if ! awk '$2=="/mnt/us"{f=1} END{exit !f}' /proc/mounts 2>/dev/null; then
  echo "ERROR: /mnt/us is not a mounted filesystem - refusing to create $DIR." >&2
  echo "Mount the Kindle userstore and try again." >&2
  exit 10
fi

mkdir -p "$DIR" 2>/dev/null

log() {
  _ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$_ts $*"
  echo "$_ts $*" >> "$LOG"
}

# --- shared pool helper (sourced, not executed) -----------------------------
if [ ! -f "$BIN/lib-pool.sh" ]; then
  log "FAIL: lib-pool.sh is missing next to this script ($BIN)."
  exit 2
fi
. "$BIN/lib-pool.sh"

# --- single instance --------------------------------------------------------
cleanup_lock() { rm -rf "$LOCK" 2>/dev/null; }
if ! mkdir "$LOCK" 2>/dev/null; then
  _oldpid=$(cat "$LOCK/pid" 2>/dev/null)
  # A lock is only trusted when the PID is alive AND its cmdline still names
  # set-screensaver.sh. A live PID that does not match is a recycled PID, so the
  # stale lock is removed and re-acquired once.
  if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null \
     && grep -qa 'set-screensaver\.sh' "/proc/$_oldpid/cmdline" 2>/dev/null; then
    log "REFUSING: another set-screensaver is running (pid $_oldpid)."
    exit 9
  fi
  rm -rf "$LOCK" 2>/dev/null
  if ! mkdir "$LOCK" 2>/dev/null; then
    log "REFUSING: could not acquire lock $LOCK."
    exit 9
  fi
fi
echo $$ > "$LOCK/pid" 2>/dev/null
trap 'cleanup_lock' EXIT
trap 'cleanup_lock; exit 130' INT TERM HUP

log "=== set-screensaver start (src=$SRC) ==="

# --- the hard gate: linkss must already be installed ------------------------
if [ ! -d "$LINKS" ]; then
  log "REFUSING: $LINKS does not exist."
  log "The ScreenSavers (linkss) hack must be installed first - see README.md."
  log "This script will not create /mnt/us/linkss: the stock framework would"
  log "never read it, and a fake directory would only mask the real problem."
  exit 2
fi

# --- source validation ------------------------------------------------------
if [ ! -f "$SRC" ]; then
  log "FAIL: source file not found: $SRC"
  exit 2
fi

if [ ! -s "$SRC" ]; then
  log "FAIL: source file is empty: $SRC"
  exit 2
fi

SIG=$(dd if="$SRC" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
if [ "$SIG" != "89504e47" ]; then
  log "FAIL: source is not a PNG (magic bytes: '$SIG')"
  exit 2
fi

DIMS=$(od -An -tu1 -j16 -N8 "$SRC" 2>/dev/null \
  | awk '{w=$1*16777216+$2*65536+$3*256+$4; h=$5*16777216+$6*65536+$7*256+$8; print w "x" h}')
if [ -z "$DIMS" ] || [ "$DIMS" != "1072x1448" ]; then
  log "FAIL: source dimensions are '${DIMS:-unknown}', expected 1072x1448 for a PW3."
  log "Refusing to install a wrong-sized screensaver (fail closed)."
  exit 2
fi

# --- ensure the destination directory exists --------------------------------
if ! mkdir -p "$SSDIR"; then
  log "FAIL: cannot create $SSDIR"
  exit 3
fi

# --- destination is ALWAYS the FW >= 5.5 final name -------------------------
# linkss reads bg_ssNN.png live from the bind-mounted pool; bg_ss00.png is the
# single file this bundle owns. Any other *.png is quarantined after install.
DEST="$SSDIR/bg_ss00.png"
log "destination screensaver: $DEST"

# --- install atomically -----------------------------------------------------
TMP="$SSDIR/.bg_ss_install.$$.tmp"
rm -f "$TMP"
if ! cp "$SRC" "$TMP"; then
  log "FAIL: copy to temp file failed"
  rm -f "$TMP"
  exit 4
fi

# Back up the existing destination once, before it is overwritten.
if [ -e "$DEST" ]; then
  if [ -e "$DEST.bak" ]; then
    log "backup already exists: $DEST.bak (kept; restore it to roll back)"
  elif cp "$DEST" "$DEST.bak"; then
    log "backup created: $DEST.bak (restore it to roll back)"
  else
    log "WARNING: could not create backup $DEST.bak"
  fi
fi

if ! mv "$TMP" "$DEST"; then
  log "FAIL: move into place failed"
  rm -f "$TMP"
  exit 5
fi

sync

# --- verify what we actually installed --------------------------------------
if [ ! -s "$DEST" ]; then
  log "ERROR: installed file is missing or empty: $DEST"
  exit 6
fi
VDIMS=$(od -An -tu1 -j16 -N8 "$DEST" 2>/dev/null \
  | awk '{w=$1*16777216+$2*65536+$3*256+$4; h=$5*16777216+$6*65536+$7*256+$8; print w "x" h}')
if [ "$VDIMS" != "1072x1448" ]; then
  log "ERROR: installed file IHDR is '${VDIMS:-unknown}', expected 1072x1448."
  exit 6
fi

# The installed basename must be exactly bg_ss00.png (the FW >= 5.5 final name),
# or linkss silently ignores the file.
INSTALLED_BASE=${DEST##*/}
if [ "$INSTALLED_BASE" != "bg_ss00.png" ]; then
  log "ERROR: installed filename '$INSTALLED_BASE' is not bg_ss00.png."
  log "linkss reads bg_ssNN.png from the bind-mounted pool; a wrong name would be ignored."
  exit 7
fi

# The install is verified: quarantine every OTHER *.png so the pool holds exactly
# one file. Files are moved, never deleted.
pool_quarantine_extras "$SSDIR" "$DEST" "$QUARANTINE"

SIZE=$(wc -c < "$DEST" 2>/dev/null)
log "installed: $DEST (${SIZE:-?} bytes, IHDR ${VDIMS})"
log "=== set-screensaver done ==="
exit 0
