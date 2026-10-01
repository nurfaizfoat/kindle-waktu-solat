#!/bin/sh
# Name: SS Board 5 Install LinksS
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-5-install-linkss.png

# Library scriptlet for the Screensaver Board bundle.
#
# Runs MRPI (MR Package Installer) to install the packages waiting in
# /mnt/us/mrpackages. This firmware has no KUAL, so MRPI is invoked directly
# with the same action its own menu.json declares:
#     ./bin/mrinstaller.sh launch_installer
# run from the MRInstaller extension directory.
#
# MRPI normally reboots the Kindle when it finishes, so the summary below may
# be cut short by that reboot. That is expected.
#
# Do NOT add a "# DontUseFBInk" line: without it, the lines printed at the end
# are painted on the device screen.

MRPI=/mnt/us/extensions/MRInstaller
PKGS=/mnt/us/mrpackages

if [ ! -f "$MRPI/bin/mrinstaller.sh" ]; then
  echo "SS Board 5 Install LinksS"
  echo "MRPI not found on this Kindle."
  echo "Expected: $MRPI/bin/mrinstaller.sh"
  echo "Copy extensions/MRInstaller onto the device, then tap this again."
  exit 1
fi

if [ ! -d "$PKGS" ]; then
  echo "SS Board 5 Install LinksS"
  echo "Package folder missing: $PKGS"
  exit 1
fi

if [ -z "$(ls -A "$PKGS" 2>/dev/null)" ]; then
  echo "SS Board 5 Install LinksS"
  echo "No packages found in $PKGS"
  echo "Copy the linkss .bin in there over USB, then tap this again."
  exit 1
fi

cd "$MRPI" || exit 1
sh ./bin/mrinstaller.sh launch_installer
RC=$?

echo ""
echo "SS Board 5 Install LinksS"
echo "Exit code: $RC"
if [ "$RC" -eq 0 ]; then
  echo "Result: MRPI finished - the Kindle should restart."
  echo "After it restarts unplugged, sleeping should show a screensaver."
else
  echo "Result: MRPI did not finish cleanly."
  echo "Check its log under $MRPI/log/"
fi
exit "$RC"
