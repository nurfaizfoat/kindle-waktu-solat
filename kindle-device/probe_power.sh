#!/bin/sh
# Name: Probe Power Events
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/icon.png

# ============================================================================
# ONE-SHOT READ-ONLY DIAGNOSTIC. TAP IT ONCE, THEN READ THE LOG OVER USB.
# ============================================================================
#
# WHY THIS EXISTS
# The dashboard should step aside and hand the screen back to the normal
# Kindle UI when the power button is pressed. That needs the real powerd event
# name, and a WRONG name makes `lipc-wait-event` block forever with no error
# at all - a silent failure. So we discover the names on the device instead of
# guessing them.
#
# WHAT THIS DOES NOT DO
# It does not stop the framework, does not touch the dashboard loop, does not
# install anything, and changes no settings. It only READS things and appends
# findings to /mnt/us/dashboard/probe.log.
#
# Every call is time-bounded so a blocking lipc wait cannot hang the probe.

DIR=/mnt/us/dashboard
OUT="$DIR/probe.log"
mkdir -p "$DIR"

# Bound each call so nothing can block indefinitely.
bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@" 2>&1
  else
    "$@" 2>&1
  fi
}

{
  echo "=== power-event probe $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "kernel: $(uname -a 2>/dev/null)"
  echo

  echo "--- 1. which relevant tools exist ---"
  for t in lipc-wait-event lipc-get-prop lipc-set-prop timeout eips rtcwake; do
    p=$(command -v "$t" 2>/dev/null)
    if [ -n "$p" ]; then
      echo "  $t -> $p"
    else
      echo "  $t -> MISSING"
    fi
  done
  echo

  echo "--- 2. readable powerd properties ---"
  for prop in state preventScreenSaver batteryLevel isCharging; do
    printf '  %s = ' "$prop"
    bounded lipc-get-prop com.lab126.powerd "$prop"
  done
  echo

  echo "--- 3. lipc-wait-event usage (may list event names) ---"
  bounded lipc-wait-event
  echo

  echo "--- 4. powerd event-name strings ---"
  if [ -r /usr/bin/powerd ]; then
    echo "  [screensaver/suspend-like tokens]"
    grep -aoE '[A-Za-z]{3,30}(ScreenSaver|Suspend|Sleep)[A-Za-z]{0,20}' /usr/bin/powerd 2>/dev/null | sort -u | head -40
    echo "  [camelCase event patterns]"
    grep -aoE 'goingTo[A-Za-z]+|outOf[A-Za-z]+|readyTo[A-Za-z]+|wakeupFrom[A-Za-z]+|entering[A-Za-z]+|Entering[A-Za-z]+' /usr/bin/powerd 2>/dev/null | sort -u | head -40
  else
    echo "  /usr/bin/powerd not readable"
  fi
  echo

  echo "--- 5. suspend / power interfaces ---"
  ls -l /sys/power/state 2>&1 | head -3
  printf '  /sys/power/state = '
  cat /sys/power/state 2>&1 | head -1
  ls -1 /sys/class/rtc 2>&1 | head -5
  echo

  echo "--- 6. lipc event configuration on disk ---"
  ls -l /usr/share/lipc* /etc/lipc* 2>&1 | head -20
  ls -l /var/local/system/ 2>&1 | head -20
  echo

  echo "=== probe complete ==="
} >> "$OUT" 2>&1

# On-screen confirmation so a tap gives visible feedback. The framework may
# repaint over it shortly, which is fine - the real output is the log file.
FBINK=""
for c in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink; do
  if [ -f "$c" ]; then
    FBINK="$c"
    break
  fi
done

if [ -n "$FBINK" ]; then
  # fbink lives on vfat with no execute bit, so run it from tmpfs.
  cp "$FBINK" /tmp/fbink_probe 2>/dev/null
  chmod 755 /tmp/fbink_probe 2>/dev/null
  if [ -x /tmp/fbink_probe ]; then
    /tmp/fbink_probe -m -y 20 "PROBE DONE" 2>/dev/null
    /tmp/fbink_probe -m -y 23 "see dashboard/probe.log" 2>/dev/null
  fi
fi

exit 0
