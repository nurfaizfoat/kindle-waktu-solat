#!/bin/sh
# Name: SS Board 1 Diagnose
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-1-diagnose.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# This entry runs the READ-ONLY diagnostic. It changes nothing on the device;
# it only collects firmware, linkss and ld-symlink information into one log.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/diagnose.sh
LOG=/mnt/us/dashboard/screensaver-diag.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 1 Diagnose"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 1 Diagnose"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: diagnostic finished OK - it only read the device."
else
  echo "Result: diagnostic did not finish - check the bundle install."
fi
echo "Log: $LOG"
exit "$RC"
