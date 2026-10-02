#!/bin/sh
# Name: SS Board 6 Auto-Refresh On
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-6-autostart-on.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# Installs and starts the screensaver-board-refresh upstart job, which refreshes
# the board on every wake from sleep and at least hourly while awake. It opens
# the rootfs read-write only inside a guarded mntroot rw/ro block and always
# returns it to read-only.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/install-refresh-autostart.sh
LOG=/mnt/us/dashboard/screensaver.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 6 Auto-Refresh On"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 6 Auto-Refresh On"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: auto-refresh installed (it starts now and again at boot; refresh on wake + at least hourly)."
elif [ "$RC" -eq 7 ]; then
  echo "Result: REBOOT REQUIRED - the rootfs was left read-write. Reboot the Kindle now."
else
  echo "Result: install did not complete. Read the log and re-run SS Board 1 Diagnose."
fi
echo "Log: $LOG"
exit "$RC"
