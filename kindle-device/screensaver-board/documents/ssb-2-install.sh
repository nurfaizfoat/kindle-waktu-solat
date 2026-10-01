#!/bin/sh
# Name: SS Board 2 Install Board
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-2-install.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# This entry fetches the current board, gates it through the on-device renderer,
# and only then installs it as the native screensaver. A failed fetch or a
# failed gate leaves the previous good board untouched.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/refresh.sh
LOG=/mnt/us/dashboard/screensaver.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 2 Install Board"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 2 Install Board"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: board installed as the screensaver. Reboot unplugged, then test sleep."
else
  echo "Result: install did not complete. The previous good board was kept."
fi
echo "Log: $LOG"
exit "$RC"
