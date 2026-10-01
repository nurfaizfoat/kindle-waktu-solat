#!/bin/sh
# RUNME.sh - the Kindle's built-in script trigger.
#
# Place at the USB ROOT (/mnt/us/RUNME.sh) and trigger from the Kindle's
# search bar with:   ;log runme
#
# Runs as root.
#
# STAGE 1 (safe: draws once, changes nothing):
#     sh /mnt/us/dashboard/test_display.sh
#
# STAGE 2 (takes over the screen: stops the framework and loops):
#     sh /mnt/us/dashboard/dashboard.sh
#
# Only one of the two should be active. The stage 1 line is commented out
# because stage 1 already passed; stage 2 is enabled.

LOG=/mnt/us/runme.log

echo "RUNME: started $(date)" > "$LOG"

# --- stage 1: one-shot display test (already passed) ---
# sh /mnt/us/dashboard/test_display.sh >> "$LOG" 2>&1

# --- stage 2: always-on dashboard loop ---
# Run detached so this script returns immediately and the search bar does not
# block. Output is captured by dashboard.sh's own log file.
nohup sh /mnt/us/dashboard/dashboard.sh >/dev/null 2>&1 &

echo "RUNME: launched dashboard (pid $!)" >> "$LOG"
echo "RUNME: done" >> "$LOG"
