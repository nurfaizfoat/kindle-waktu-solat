#!/bin/sh
# Name: SS Board 7 Auto-Refresh Off
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-7-autostart-off.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# Rollback for entry 6: stops the refresh daemon and removes the
# screensaver-board-refresh upstart job inside a guarded mntroot rw/ro block.
# It is idempotent and always returns the rootfs to read-only.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/remove-refresh-autostart.sh
LOG=/mnt/us/dashboard/screensaver.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 7 Auto-Refresh Off"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 7 Auto-Refresh Off"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: auto-refresh stopped and removed."
elif [ "$RC" -eq 7 ]; then
  echo "Result: REBOOT REQUIRED - the job was removed but the rootfs is still read-write. Reboot the Kindle now."
else
  echo "Result: rollback did not complete. Read the log."
fi
echo "Log: $LOG"
exit "$RC"
