#!/bin/sh
#
# set-screensaver.sh - install a PNG as the ONE native Kindle screensaver.
#
# WHY THIS EXISTS
#   The linkss ScreenSavers hack reads custom images from
#   /mnt/us/linkss/screensavers/. Placing a single file named
#   bg_<group>_ss00.png there makes closing the lid show that image and opening
#   the lid return to reading - the native sleep path, with no framebuffer
#   takeover and no clock/battery chrome drawn over the board.
#
# WHY EXACTLY ONE FILE
#   With several bg_* files present, linkss cycles through them, which makes the
#   board appear on some sleeps and not others. This script NEVER deletes files
#   it does not own: if extras exist it WARNs and leaves them alone.
#
# PANEL GROUP
#   The bg_<group>_ss<NN> token is panel-size dependent. Because the source image
#   is hard-gated to 1072x1448, the expected group is derived from the panel:
#   "large" for a PW3. An existing bg_large_ss*.png is reused by exact filename,
#   otherwise bg_large_ss00.png is installed. Files for any other group are
#   ignored by linkss and are reported as a warning, never used to pick a name.
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
#   - Writes only /mnt/us/dashboard/screensaver.log and the linkss screensaver.
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

# --- single instance --------------------------------------------------------
cleanup_lock() { rm -rf "$LOCK" 2>/dev/null; }
if ! mkdir "$LOCK" 2>/dev/null; then
  _oldpid=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null; then
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

# --- choose the panel group -------------------------------------------------
# The expected group is derived from the panel size, not from whatever bg_*
# file happens to be present: a 1072x1448 (PW3) panel uses linkss group "large".
EXPECTED_GROUP="large"

GROUP="$EXPECTED_GROUP"
GROUP_SRC=""

# Reuse an existing bg_large_ss*.png verbatim if one is present, so we do not
# create a duplicate that would make linkss cycle between images.
for f in "$SSDIR"/bg_"$EXPECTED_GROUP"_ss*.png; do
  [ -e "$f" ] || continue
  GROUP_SRC="$f"
  break
done

if [ -n "$GROUP_SRC" ]; then
  DEST="$GROUP_SRC"
  log "panel group '$EXPECTED_GROUP' reused from existing file: $GROUP_SRC"
else
  DEST="$SSDIR/bg_${EXPECTED_GROUP}_ss00.png"
  log "no existing bg_${EXPECTED_GROUP}_ss*.png found; installing $DEST"
  log "(the 1072x1448 PW3 panel uses the linkss group '$EXPECTED_GROUP')."
fi

# Warn about files belonging to a different (wrong) panel group: linkss ignores
# them for this panel, and they must never drive the group choice.
OTHER_GROUP=""
for f in "$SSDIR"/bg_*_ss*.png; do
  [ -e "$f" ] || continue
  [ "$f" = "$DEST" ] && continue
  _b=${f##*/}
  _g=${_b#bg_}
  _g=${_g%%_ss*}
  [ "$_g" = "$EXPECTED_GROUP" ] && continue
  OTHER_GROUP="$OTHER_GROUP $f"
done
if [ -n "$OTHER_GROUP" ]; then
  log "WARNING: screensaver files for a DIFFERENT panel group exist and will be IGNORED:"
  for f in $OTHER_GROUP; do log "    $f"; done
  log "WARNING: linkss only reads the '$EXPECTED_GROUP' group on this 1072x1448 panel."
  log "The group is derived from panel size; these files belong to another panel."
fi

# --- NEVER delete files we do not own; warn about extras --------------------
EXTRAS=""
for f in "$SSDIR"/bg_*.png; do
  [ -e "$f" ] || continue
  [ "$f" = "$DEST" ] && continue
  EXTRAS="$EXTRAS $f"
done
if [ -n "$EXTRAS" ]; then
  log "WARNING: other screensaver files exist and are NOT managed by this bundle:"
  for f in $EXTRAS; do log "    $f"; done
  log "WARNING: extras can cause unpredictable cycling in linkss."
  log "Remove them manually if you want exactly one screensaver."
fi

# --- install atomically -----------------------------------------------------
TMP="$SSDIR/.bg_${GROUP}_ss00.$$.tmp"
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

# The filename group token must equal the expected group, or linkss silently
# ignores the file (e.g. bg_medium_ss00.png on a 1072x1448 PW3).
INSTALLED_BASE=${DEST##*/}
INSTALLED_GROUP=${INSTALLED_BASE#bg_}
INSTALLED_GROUP=${INSTALLED_GROUP%%_ss*}
if [ "$INSTALLED_GROUP" != "$EXPECTED_GROUP" ]; then
  log "ERROR: installed filename group is '$INSTALLED_GROUP', expected '$EXPECTED_GROUP'."
  log "linkss would ignore '$INSTALLED_BASE' on this 1072x1448 panel."
  exit 7
fi

SIZE=$(wc -c < "$DEST" 2>/dev/null)
log "installed: $DEST (${SIZE:-?} bytes, IHDR ${VDIMS})"
log "=== set-screensaver done ==="
exit 0
