#!/bin/sh
# Name: SS Board 4 Undo Firmware Fix
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-4-undo-ld.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# Rollback for entry 3: removes ONLY the /lib/ld-linux.so.3 symlink that the
# firmware fix creates, and only when it points at /lib/ld-linux-armhf.so.3.
# Everything else is left alone, and the rootfs ends read-only.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/remove-ldsymlink.sh
LOG=/mnt/us/dashboard/screensaver.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 4 Undo Firmware Fix"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 4 Undo Firmware Fix"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: firmware fix removed. Reboot unplugged when convenient."
else
  echo "Result: undo did not complete. The symlink was left untouched."
fi
echo "Log: $LOG"
exit "$RC"
