#!/bin/sh
# Name: Stop Waktu Solat
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/stop-icon.png

# ============================================================================
# STOP / RECOVERY BUTTON
# ============================================================================
#
# WHY THIS IS NEEDED
# The dashboard stops the Kindle framework to hold the screen, which also hides
# the library - so while it runs normally you CANNOT tap a stop button. This is
# for the two cases where you can see the library:
#
#   1. A stray instance is still painting over whatever you open (this is what
#      happened: two pre-guard loops kept refreshing the panel every 5 minutes).
#   2. The dashboard is already stopped and you just want to be sure.
#
# Normal ways to stop a correctly behaved dashboard remain: hold power to
# reboot, or create /mnt/us/dashboard/stop over USB.

DIR=/mnt/us/dashboard
LOG="$DIR/dashboard.log"
STOP="$DIR/stop"
PIDFILE="$DIR/dashboard.pid"

mkdir -p "$DIR"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

log "=== stop requested from library ==="

# --- 1. raise the cooperative flag -----------------------------------------
# Well-behaved instances exit on their own when they see it.
touch "$STOP"

# --- 2. terminate whatever is still alive ----------------------------------
# Matching '/dashboard\.sh' includes the path separator on purpose: it matches
# the real loop at /mnt/us/dashboard/dashboard.sh but NOT this script, whose
# path ends in '/stop-dashboard.sh'. $$ is also skipped as a belt-and-braces
# guard so this script can never kill itself.
SELF=$$
KILLED=0
for proc in /proc/[0-9]*; do
  pid=${proc#/proc/}
  [ "$pid" = "$SELF" ] && continue
  if grep -qa '/dashboard\.sh' "$proc/cmdline" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null && KILLED=$((KILLED + 1))
  fi
done
log "terminated $KILLED dashboard instance(s) with SIGTERM"

# Give the cleanup traps a moment to restart the framework.
sleep 3

# --- 3. anything that ignored SIGTERM gets SIGKILL --------------------------
STUBBORN=0
for proc in /proc/[0-9]*; do
  pid=${proc#/proc/}
  [ "$pid" = "$SELF" ] && continue
  if grep -qa '/dashboard\.sh' "$proc/cmdline" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null && STUBBORN=$((STUBBORN + 1))
  fi
done
[ "$STUBBORN" -gt 0 ] && log "force-killed $STUBBORN stubborn instance(s)"

# --- 4. clear control files so the next start begins clean ------------------
rm -f "$STOP" "$PIDFILE"

# --- 5. make sure the normal Kindle UI is back ------------------------------
# Also drop the screensaver suppression the dashboard set, or the device would
# stay awake until the next reboot.
lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
/etc/init.d/framework start >/dev/null 2>&1
log "framework started, screensaver restored"

# --- 6. on-screen confirmation ---------------------------------------------
FBINK=""
for c in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink; do
  if [ -f "$c" ]; then
    FBINK="$c"
    break
  fi
done

if [ -n "$FBINK" ]; then
  # fbink is on vfat with no execute bit, so run it from tmpfs.
  cp "$FBINK" /tmp/fbink_stop 2>/dev/null
  chmod 755 /tmp/fbink_stop 2>/dev/null
  if [ -x /tmp/fbink_stop ]; then
    /tmp/fbink_stop -m -y 20 "DASHBOARD STOPPED" 2>/dev/null
    /tmp/fbink_stop -m -y 23 "killed ${KILLED} instance(s)" 2>/dev/null
  fi
fi

exit 0
