#!/bin/sh
# Name: Waktu Solat
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/icon.png
# DontUseFBInk

# Library launcher for the always-on waktu-solat dashboard.
#
# HOW IT WORKS
#   The dashboard stops the Kindle framework so nothing repaints over the
#   board, then refreshes it every 5 minutes.
#
# WHY THE SCREEN "STAYS" ON THE BOARD
#   E-ink holds an image with zero power draw, so the board simply sits there.
#
# HOW TO STOP IT
#   Stopping the framework also hides the library, so there is no on-screen
#   button to stop it. Two ways out, both of which restore normal behaviour:
#     1. Reboot the Kindle (hold power ~40s).
#     2. Plug in over USB and create an empty file at /mnt/us/dashboard/stop
#        The loop notices it, exits, and restarts the framework.
#
# Nothing here is installed as a startup item, so a reboot always returns the
# Kindle to its normal UI.

nohup sh /mnt/us/dashboard/dashboard.sh >/dev/null 2>&1 &
