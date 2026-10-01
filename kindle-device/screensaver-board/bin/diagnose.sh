#!/bin/sh
#
# diagnose.sh - READ-ONLY screensaver-stack diagnostic.
#
# WHY THIS EXISTS
#   Kindle firmware 5.16.2.1.1 sits in the gap the ScreenSavers (linkss) hack
#   was never tested against: the classic hack is confirmed on 5.12.2 and
#   reported broken on 5.17+, where a missing /lib/ld-linux.so.3 is the usual
#   cause. This script captures everything needed to tell which world we are in
#   BEFORE anything is installed, so a failure can be diagnosed from the host
#   over USB.
#
# SAFETY
#   READ-ONLY apart from its own log. The ONLY file this script writes is
#       /mnt/us/dashboard/screensaver-diag.log
#   It will best-effort create /mnt/us/dashboard ONLY when /mnt/us is an actual
#   mountpoint, so the log is always reachable over USB. If /mnt/us is not
#   mounted it refuses and writes nothing.
#
# Log: /mnt/us/dashboard/screensaver-diag.log

set -u

DIR=/mnt/us/dashboard
LOG="$DIR/screensaver-diag.log"

# --- /mnt/us must be a real mount; only then may we create the log dir -------
if ! awk '$2=="/mnt/us"{f=1} END{exit !f}' /proc/mounts 2>/dev/null; then
  echo "ERROR: /mnt/us is not a mounted filesystem." >&2
  echo "Reconnect the Kindle userstore and try again." >&2
  exit 1
fi

if ! mkdir -p "$DIR" 2>/dev/null; then
  echo "ERROR: cannot create $DIR on the mounted userstore." >&2
  exit 1
fi

# Keep the real stdout so the KUAL user still gets a summary; then send every
# other write into the single permitted log file.
exec 3>&1 || exit 1
exec >> "$LOG" 2>&1 || exit 1

echo "=============================================================="
echo "screensaver diagnostics - $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================================="

section() {
  echo ""
  echo "=== $1 ==="
}

section "date"
date 2>&1

section "uname"
uname -a 2>&1

section "firmware version"
echo "-- /etc/version --"
if [ -r /etc/version ]; then cat /etc/version 2>&1; else echo "(not readable)"; fi
echo "-- /mnt/us/system/version.txt --"
if [ -r /mnt/us/system/version.txt ]; then cat /mnt/us/system/version.txt 2>&1; else echo "(not readable)"; fi

section "process list"
# Prefer the full listing; fall back to bare ps on busybox builds that reject it.
ps aux 2>&1 || ps 2>&1 || echo "(ps unavailable)"

section "initctl list"
if command -v initctl >/dev/null 2>&1; then
  initctl list 2>&1 || echo "(initctl list failed)"
else
  echo "(initctl not present on this firmware)"
fi

section "linkss (ScreenSavers hack) on userstore"
if [ -d /mnt/us/linkss ]; then
  ls -la /mnt/us/linkss 2>&1
  if [ -d /mnt/us/linkss/screensavers ]; then
    echo "-- /mnt/us/linkss/screensavers --"
    ls -la /mnt/us/linkss/screensavers 2>&1
  fi
else
  echo "(missing: /mnt/us/linkss - ScreenSavers hack NOT installed)"
fi

section "blanket screensaver (rootfs)"
if [ -d /usr/share/blanket ]; then
  ls -la /usr/share/blanket 2>&1
else
  echo "(missing or unreadable: /usr/share/blanket)"
fi
if [ -d /usr/share/blanket/screensaver ]; then
  echo "-- /usr/share/blanket/screensaver --"
  ls -la /usr/share/blanket/screensaver 2>&1
else
  echo "(missing or unreadable: /usr/share/blanket/screensaver)"
fi

section "lipc powerd properties"
if command -v lipc-get-prop >/dev/null 2>&1; then
  for p in preventScreenSaver powerButton status; do
    printf 'com.lab126.powerd %s = ' "$p"
    # shellcheck disable=SC2086
    lipc-get-prop com.lab126.powerd $p 2>&1 || echo "(query failed)"
  done
else
  echo "(lipc-get-prop not present)"
fi

section "ld-linux symlink (5.17+ workaround check)"
if [ -L /lib/ld-linux.so.3 ] || [ -e /lib/ld-linux.so.3 ]; then
  ls -l /lib/ld-linux.so.3 2>&1
else
  echo "(missing: /lib/ld-linux.so.3 does not exist)"
fi
if [ -L /lib/ld-linux-armhf.so.3 ] || [ -e /lib/ld-linux-armhf.so.3 ]; then
  ls -l /lib/ld-linux-armhf.so.3 2>&1
else
  echo "(missing: /lib/ld-linux-armhf.so.3 does not exist)"
fi

section "end"
echo "diagnostics written to $LOG"

# User-facing summary on the KUAL console (fd 3 is the untouched stdout).
echo "Screensaver diagnostics written to:" >&3
echo "  $LOG" >&3
echo "Read it over USB from the Kindle drive." >&3

exit 0
