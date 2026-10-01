#!/bin/sh
#
# test-format.sh - cheap gate: will the device renderer accept this PNG?
#
# WHY THIS EXISTS
#   dashboard/board.png is currently a 4-bit COLORMAP PNG. NiLuJe's ScreenSavers
#   documentation warns that 16-colour-indexed PNGs can make FW 5.x give up on
#   screensavers until the next reboot. This script draws the file with the
#   stock renderer (/usr/sbin/eips), which shares the framebuffer path the
#   screensaver engine uses, so a success here is strong evidence the file is
#   safe BEFORE anything is installed.
#
# SAFETY
#   Draws once and exits. Writes only /mnt/us/dashboard/screensaver.log.
#
# Usage: test-format.sh [png-path]   (default /mnt/us/dashboard/board.png)
# Log:   /mnt/us/dashboard/screensaver.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver.log"
IMG="${1:-/mnt/us/dashboard/board.png}"
EIPS=/usr/sbin/eips

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

log "=== test-format start (file=$IMG) ==="

if [ ! -f "$IMG" ]; then
  log "FAIL: file not found: $IMG"
  exit 2
fi

if [ ! -s "$IMG" ]; then
  log "FAIL: file is empty: $IMG"
  exit 2
fi

# --- PNG magic --------------------------------------------------------------
SIG=$(dd if="$IMG" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
if [ "$SIG" != "89504e47" ]; then
  log "FAIL: not a PNG (magic bytes: '$SIG')"
  exit 2
fi
log "magic OK (89504e47)"

# --- dimensions from the IHDR chunk (bytes 16..23) --------------------------
DIMS=$(od -An -tu1 -j16 -N8 "$IMG" 2>/dev/null \
  | awk '{w=$1*16777216+$2*65536+$3*256+$4; h=$5*16777216+$6*65536+$7*256+$8; print w "x" h}')
if [ -z "$DIMS" ]; then
  log "FAIL: could not read IHDR dimensions"
  log "=== test-format done (FAILED) ==="
  exit 2
fi
log "dimensions: $DIMS (expected 1072x1448)"
if [ "$DIMS" != "1072x1448" ]; then
  log "FAIL: dimensions are $DIMS, not 1072x1448 for a PW3"
  log "=== test-format done (FAILED) ==="
  exit 2
fi

# --- device renderer test ---------------------------------------------------
if [ ! -x "$EIPS" ]; then
  log "FAIL: $EIPS not found or not executable - cannot test on the device"
  exit 3
fi

log "running: $EIPS -f -g $IMG"
OUT=$("$EIPS" -f -g "$IMG" 2>&1)
RC=$?
log "eips exit=$RC output: $OUT"

if [ "$RC" -eq 0 ]; then
  log "PASS: device renderer accepted the PNG (eips exit 0)"
  log "=== test-format done ==="
  exit 0
fi

log "FAIL: eips returned $RC - device renderer rejected the PNG"
log "If the screen did not change, re-encode the board to 8-bit first (see to-png8.sh / README.md)."
log "=== test-format done (FAILED) ==="
exit 1
