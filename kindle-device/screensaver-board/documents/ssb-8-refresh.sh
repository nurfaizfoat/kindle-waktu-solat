#!/bin/sh
# Name: Refresh Waktu Solat
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-8-refresh.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# This is the everyday, one-tap entry: it fetches the latest board, gates it
# through the on-device renderer, and installs it as the native screensaver.
# It then prints WHY the run succeeded or failed (from the reason file that
# refresh.sh writes), so a failure is readable on the device screen without a PC.
#
# A failed fetch or a failed gate leaves the previous good board untouched.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/refresh.sh
LOG=/mnt/us/dashboard/screensaver.log
REASON=/mnt/us/dashboard/refresh-last-reason

if [ ! -f "$SCRIPT" ]; then
  echo "Refresh Waktu Solat"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

echo "Refresh Waktu Solat"
echo "Fetching the latest board..."
echo ""

sh "$SCRIPT"
RC=$?

echo ""
echo "Refresh Waktu Solat"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: board updated. It appears at the next sleep."
elif [ "$RC" -eq 8 ]; then
  echo "Result: board URL not configured."
  echo "Set BOARD_URL in /mnt/us/dashboard/board-url.conf."
elif [ "$RC" -eq 1 ]; then
  echo "Result: could not fetch the board."
  echo "Network problem, or the server did not return a PNG."
elif [ "$RC" -eq 9 ]; then
  echo "Result: another refresh is already running. Try again shortly."
else
  echo "Result: refresh did not complete (exit $RC)."
  echo "See the reason and log below."
fi
echo ""
if [ -s "$REASON" ]; then
  echo "Why:"
  cat "$REASON"
else
  echo "Why: (no reason recorded - see the log)"
fi
echo ""
echo "Log: $LOG"
exit "$RC"
