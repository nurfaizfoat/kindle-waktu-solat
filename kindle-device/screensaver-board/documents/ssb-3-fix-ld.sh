#!/bin/sh
# Name: SS Board 3 Firmware Fix
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-3-fix-ld.png

# Library scriptlet for the Screensaver Board bundle.
# The Kindle shows this file in the library as a tappable book, so it is the
# launcher on this firmware (there is no KUAL or Kindlet launcher here).
#
# Use this ONLY if the ScreenSavers (linkss) hack installs but never shows a
# screensaver. It applies the 5.17+ /lib/ld-linux.so.3 workaround inside a
# guarded mntroot rw/ro block and always returns the rootfs to read-only.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

SCRIPT=/mnt/us/extensions/screensaver-board/bin/prepare-ldsymlink.sh
LOG=/mnt/us/dashboard/screensaver.log

if [ ! -f "$SCRIPT" ]; then
  echo "SS Board 3 Firmware Fix"
  echo "Bundle not found on this Kindle."
  echo "Expected: $SCRIPT"
  echo "Copy extensions/screensaver-board onto the device, then tap this entry again."
  exit 1
fi

sh "$SCRIPT"
RC=$?

echo ""
echo "SS Board 3 Firmware Fix"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: firmware fix applied. Reboot unplugged, then test the screensaver."
else
  echo "Result: fix did not complete. The rootfs was left read-only and unchanged."
fi
echo "Log: $LOG"
exit "$RC"
