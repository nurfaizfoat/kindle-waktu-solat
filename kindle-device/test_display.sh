#!/bin/sh
# Stage 1 test: prove the three things that must work, and nothing more.
#   1. fbink can be found
#   2. the board can be downloaded over the Kindle's wifi
#   3. fbink can actually paint it on the e-ink panel
#
# Draws the board ONCE. No loop. No framework changes. Nothing persistent.
# If this looks wrong you have lost nothing.

# --- board URL configuration ------------------------------------------------
# The board URL is NOT hard-coded. It is read from a user-editable file that is
# sourced as a POSIX sh fragment, so it can be changed over USB without editing
# this script:
#     /mnt/us/dashboard/board-url.conf
# The placeholder below is the fallback used when that file is missing or
# unreadable; it is checked and rejected below.
BOARD_URL="https://example.com/waktu/board.php"
BOARD_URL_CONF="/mnt/us/dashboard/board-url.conf"
if [ -r "$BOARD_URL_CONF" ]; then
  . "$BOARD_URL_CONF"
fi

DIR="/mnt/us/dashboard"
IMG="$DIR/board.png"

# Refuse to fetch anything until the user has pointed BOARD_URL at their own
# board deployment. The placeholder is never a real host.
if [ -z "${BOARD_URL:-}" ] || [ "$BOARD_URL" = "https://example.com/waktu/board.php" ]; then
  echo "FAIL: the board URL is not configured."
  echo "Create $BOARD_URL_CONF with a BOARD_URL line, for example:"
  echo '    BOARD_URL="https://your-host/path/board.php"'
  echo "Template: kindle-device/board-url.conf.sample in the repository."
  echo "Refusing to fetch until it is configured."
  exit 1
fi

echo "=== kindle board: stage 1 display test ==="
echo

# --- locate fbink ---------------------------------------------------------
# The USB partition is mounted with 'showexec', so a binary with no extension
# gets NO execute bit and cannot be run in place. Try direct execution first,
# then fall back to copying it onto tmpfs (/tmp is RAM and always executable).
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
        echo "note: $c had no execute bit; copied it to /tmp/fbink"
        break
      fi
    fi
  done
fi

if [ -z "$FBINK" ]; then
  echo "FAIL: could not obtain an executable fbink."
  echo "Searched: /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink"
  echo "          /usr/bin/fbink /usr/local/bin/fbink"
  exit 1
fi
echo "fbink: $FBINK"

# Report what fbink thinks the device is. Cheap, and it proves the binary
# actually runs before we ask it to draw anything.
"$FBINK" -e 2>/dev/null | tr ';' '\n' | grep -i -E 'FBINK_VERSION|deviceName|screenWidth|screenHeight|BPP' | head -6

mkdir -p "$DIR"

# --- download -------------------------------------------------------------
echo "fetching: $BOARD_URL"
rm -f "$IMG"

if command -v curl >/dev/null 2>&1; then
  curl -s -m 30 -o "$IMG" "$BOARD_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$IMG" "$BOARD_URL"
else
  echo "FAIL: neither curl nor wget is available"
  exit 1
fi

if [ ! -s "$IMG" ]; then
  echo "FAIL: download produced nothing."
  echo "Check that wifi is ON (airplane mode OFF) and the URL is reachable."
  exit 1
fi

# --- verify it is really a PNG -------------------------------------------
# A failed request returns an error page, which fbink would refuse to draw.
# Catch that here so the reason is obvious.
SIG=$(dd if="$IMG" bs=1 count=4 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
SIZE=$(wc -c < "$IMG")

if [ "$SIG" != "89504e47" ]; then
  echo "FAIL: downloaded file is not a PNG (magic bytes: $SIG, $SIZE bytes)"
  echo "Server returned:"
  head -c 300 "$IMG"
  echo
  exit 1
fi
echo "downloaded OK: $SIZE bytes, valid PNG"

# --- paint ----------------------------------------------------------------
echo "painting with fbink (GC16 = 16-level greyscale)..."
"$FBINK" -g file="$IMG",halign=CENTER,valign=CENTER -W GC16
RC=$?
echo "fbink exit code: $RC"

echo
if [ "$RC" -eq 0 ]; then
  echo "=== STAGE 1 PASSED ==="
  echo "The screen should now show the waktu-solat board."
  echo "The stock Kindle UI may repaint over it when it wakes - that is expected"
  echo "at this stage and is what stage 2 solves."
else
  echo "=== STAGE 1 FAILED (fbink returned $RC) ==="
  echo "The download worked, so wifi and the URL are fine."
  echo "The problem is fbink itself - check the error above."
fi
