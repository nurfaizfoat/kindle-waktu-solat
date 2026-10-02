#!/bin/sh
#
# refresh.sh - fetch the current board and install it as the screensaver.
#
# FLOW
#   1. Fetch the board URL into a unique temp file (PNG magic-byte and
#      size-cap checks, same URL as dashboard.sh).
#   2. Normalise to an 8-bit PNG on-device (linkss ships ImageMagick), because
#      the server emits 4-bit and the device renderer rejects that.
#   3. Gate the NORMALISED file with test-format.sh, letting the renderer pick
#      between the grayscale and palette-8 candidates.
#   4. Only after the gate passes, move it over board.png and delegate to
#      set-screensaver.sh.
#
# SAFETY
#   - Refuses to run if /mnt/us is not a mounted filesystem.
#   - Single-instance pidfile so two KUAL taps cannot race.
#   - Downloads are capped in size; both curl and wget get a timeout.
#   - A failed fetch or gate leaves the previous good board.png untouched.
#   - The previous board.png is backed up to board.png.bak before replacement.
#   - Writes only under /mnt/us/dashboard and the linkss screensaver path. It
#     never stops the framework and never touches the running dashboard.
#
# Log: /mnt/us/dashboard/screensaver.log

set -u

# --- board URL configuration ------------------------------------------------
# The board URL is NOT hard-coded. It is read from a user-editable file that is
# sourced as a POSIX sh fragment, so it can be changed over USB without editing
# this script:
#     /mnt/us/dashboard/board-url.conf
# The placeholder below is the fallback used when that file is missing or
# unreadable; it is checked and rejected further down.
BOARD_URL="https://example.com/waktu/board.php"
BOARD_URL_CONF="/mnt/us/dashboard/board-url.conf"
DIR=/mnt/us/dashboard
IMG="$DIR/board.png"
TMP="$DIR/board.png.$$.tmp"
LOG="$DIR/screensaver.log"
LOCK="$DIR/refresh.lock"
MAXBYTES=2097152
BIN=$(cd "$(dirname "$0")" && pwd)
CONV_TMP=""

# --- /mnt/us must be a real mount, or we would fabricate a dead dashboard dir
if ! awk '$2=="/mnt/us"{f=1} END{exit !f}' /proc/mounts 2>/dev/null; then
  echo "ERROR: /mnt/us is not a mounted filesystem - refusing to create $DIR." >&2
  echo "Mount the Kindle userstore and try again." >&2
  exit 10
fi

mkdir -p "$DIR" 2>/dev/null

# The URL config lives on the userstore, so it is read only once /mnt/us is
# confirmed mounted; sourcing it before the guard could pick up a shadow file.
if [ -r "$BOARD_URL_CONF" ]; then
  . "$BOARD_URL_CONF"
fi

log() {
  _ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$_ts $*"
  echo "$_ts $*" >> "$LOG"
}

# --- configuration check ----------------------------------------------------
# Refuse to fetch anything until the user has pointed BOARD_URL at their own
# board deployment. The placeholder is never a real host.
if [ -z "${BOARD_URL:-}" ] || [ "$BOARD_URL" = "https://example.com/waktu/board.php" ]; then
  log "ERROR: the board URL is not configured."
  log "Create $BOARD_URL_CONF with a BOARD_URL line, for example:"
  log "    BOARD_URL=\"https://your-host/path/board.php\""
  log "Template: kindle-device/board-url.conf.sample in the repository."
  log "Refusing to fetch until it is configured."
  exit 8
fi

# --- single instance --------------------------------------------------------
cleanup_lock() {
  rm -rf "$LOCK" 2>/dev/null
  [ -n "${CONV_TMP:-}" ] && rm -f "$CONV_TMP" 2>/dev/null
}
if ! mkdir "$LOCK" 2>/dev/null; then
  _oldpid=$(cat "$LOCK/pid" 2>/dev/null)
  # A lock is only trusted when the PID is alive AND its cmdline still names
  # refresh.sh. A live PID that does not match is a recycled PID, so the stale
  # lock is removed and re-acquired once.
  if [ -n "${_oldpid:-}" ] && kill -0 "$_oldpid" 2>/dev/null \
     && grep -qa 'refresh\.sh' "/proc/$_oldpid/cmdline" 2>/dev/null; then
    log "REFUSING: another refresh is running (pid $_oldpid)."
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

# --- fetch + validate (mirrors dashboard.sh) --------------------------------
fetch_board() {
  rm -f "$TMP"

  if command -v curl >/dev/null 2>&1; then
    curl -s -m 30 --max-filesize "$MAXBYTES" -o "$TMP" "$BOARD_URL" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 30 -O "$TMP" "$BOARD_URL" || return 1
  else
    return 1
  fi

  [ -s "$TMP" ] || return 1

  # Enforce the size cap for both branches (wget has no portable max-size flag).
  _size=$(wc -c < "$TMP" 2>/dev/null)
  if [ -n "$_size" ] && [ "$_size" -gt "$MAXBYTES" ]; then
    log "FAIL: download is ${_size} bytes, over the ${MAXBYTES}-byte cap - rejected."
    rm -f "$TMP"
    return 1
  fi

  SIG=$(dd if="$TMP" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
  [ "$SIG" = "89504e47" ] || return 1

  return 0
}

log "=== refresh start ==="

if ! fetch_board; then
  log "FAIL: fetch failed (network down, server unreachable, or over size cap)."
  log "Keeping the existing $IMG unchanged."
  rm -f "$TMP"
  exit 1
fi

# --- normalise to 8-bit, then gate ------------------------------------------
# The server renders a 4-bit palette PNG, and the device renderer rejects that
# outright:
#     eips: paint_image> cannot open "...":8bit only
# The linkss hack ships a real ImageMagick under /mnt/us/linkss/bin, so we
# normalise ON-DEVICE instead of depending on the server being changed.
CONV=""
for _c in /mnt/us/linkss/bin/convert /mnt/us/linkss/bin/mogrify; do
  if [ -f "$_c" ]; then CONV="$_c"; break; fi
done

# vfat keeps no execute bit, so run the binary from tmpfs. A per-PID name avoids
# two concurrent refreshes sharing (and clobbering) one predictable root temp.
CONV_RUN=""
if [ -n "$CONV" ]; then
  CONV_TMP="/tmp/linkss_convert.$$"
  if cp -f "$CONV" "$CONV_TMP" 2>/dev/null; then
    chmod 755 "$CONV_TMP" 2>/dev/null
    [ -x "$CONV_TMP" ] && CONV_RUN="$CONV_TMP"
  fi
fi

GATE_SRC=""
if [ -n "$CONV_RUN" ]; then
  # Try each acceptable 8-bit form and let the renderer itself choose.
  for _mode in gray pal8; do
    _out="$DIR/board.norm.$_mode.$$.png"
    rm -f "$_out"
    if [ "$_mode" = "gray" ]; then
      "$CONV_RUN" "$TMP" -colorspace Gray -depth 8 "$_out" 2>>"$LOG" || continue
    else
      "$CONV_RUN" "$TMP" -colors 256 -depth 8 PNG8:"$_out" 2>>"$LOG" || continue
    fi
    [ -s "$_out" ] || continue
    if [ -f "$BIN/test-format.sh" ] && sh "$BIN/test-format.sh" "$_out"; then
      log "normalised to 8-bit ($_mode) and accepted by the renderer"
      GATE_SRC="$_out"
      break
    fi
    log "note: the $_mode candidate was rejected by the renderer"
    rm -f "$_out"
  done
else
  log "note: linkss ImageMagick not found - gating the file exactly as fetched"
fi

if [ -z "$GATE_SRC" ] && [ -f "$BIN/test-format.sh" ]; then
  sh "$BIN/test-format.sh" "$TMP" && GATE_SRC="$TMP"
fi

if [ -z "$GATE_SRC" ]; then
  log "REFUSING to install: the device renderer rejected this board."
  log "Preserved the previous good board at $IMG (not overwritten)."
  log "See to-png8.py / README.md for the host-side re-encode."
  rm -f "$TMP" "$DIR"/board.norm.*.$$.png
  exit 3
fi

# --- gate passed: only now replace the good board ---------------------------
# Back up the last-known-good board immediately before replacing it.
BAK="$DIR/board.png.bak"
if [ -e "$IMG" ]; then
  if cp "$IMG" "$BAK"; then
    log "backup created: $BAK (last-known-good board preserved)"
  else
    log "FAIL: could not back up $IMG to $BAK - refusing to replace it."
    rm -f "$TMP" "$DIR"/board.norm.*.$$.png
    exit 2
  fi
fi

if ! mv "$GATE_SRC" "$IMG"; then
  log "FAIL: could not move the normalised file into place"
  rm -f "$TMP" "$DIR"/board.norm.*.$$.png
  exit 2
fi
[ "$GATE_SRC" = "$TMP" ] || rm -f "$TMP"
log "fetched OK: $IMG ($(wc -c < "$IMG") bytes)"

# --- install -----------------------------------------------------------------
if [ ! -f "$BIN/set-screensaver.sh" ]; then
  log "FAIL: set-screensaver.sh is missing"
  exit 4
fi

sh "$BIN/set-screensaver.sh" "$IMG"
RC=$?
log "set-screensaver exit=$RC"

log "=== refresh done ==="
exit "$RC"
