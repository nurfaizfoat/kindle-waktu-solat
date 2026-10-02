#!/bin/sh
#
# test-pool.sh - HOST-ONLY tests for bin/lib-pool.sh.
#
# This file is never deployed to the Kindle. It sources the pool helper, defines
# a log() the helper can call, and enforces the bundle's core invariant:
#
#   after set-screensaver.sh installs the board, the linkss pool holds EXACTLY
#   ONE *.png file and that file is bg_ss00.png; every other *.png is moved
#   (never deleted) to the quarantine dir.
#
# Each scenario emulates the real call order: the destination bg_ss00.png is
# installed first, then pool_quarantine_extras runs. The assertion therefore
# fails if the helper quarantines the destination itself (which would leave the
# pool with zero files and a blank screensaver).

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../bin/lib-pool.sh"

log() { echo "      $*"; }

BASE="/tmp/test-pool.$$"
rm -rf "$BASE"
mkdir -p "$BASE"

FAILS=0

# assert_pool <case> <pool> <qdir> <expected-extra>...
#   The pool MUST contain exactly one *.png and it MUST be bg_ss00.png (the
#   destination survives). Every expected extra name must now exist in the
#   quarantine dir.
assert_pool() {
  _case="$1"; _pool="$2"; _qdir="$3"; shift 3
  _count=0
  for _f in "$_pool"/*.png; do
    [ -e "$_f" ] || continue
    _count=$((_count + 1))
  done

  _ok=1
  if [ "$_count" -ne 1 ]; then
    echo "FAIL $_case: expected exactly one *.png in the pool, found $_count"
    _ok=0
  elif [ ! -e "$_pool/bg_ss00.png" ]; then
    echo "FAIL $_case: the surviving pool file is not bg_ss00.png"
    _ok=0
  fi
  for _e in "$@"; do
    if [ ! -e "$_qdir/$_e" ]; then
      echo "FAIL $_case: expected quarantined file $_e"
      _ok=0
    fi
  done

  if [ "$_ok" -eq 1 ]; then
    echo "PASS $_case"
  else
    FAILS=$((FAILS + 1))
  fi
}

mkscenario() {
  _dir="$1"
  rm -rf "$_dir"
  mkdir -p "$_dir/pool" "$_dir/q"
}

# install_then_quarantine <dir>
#   Emulates set-screensaver.sh: ensure the destination exists (the "install"),
#   then quarantine everything else. This ordering is why the dest must survive.
install_then_quarantine() {
  _dir="$1"
  [ -e "$_dir/pool/bg_ss00.png" ] || : > "$_dir/pool/bg_ss00.png"
  pool_quarantine_extras "$_dir/pool" "$_dir/pool/bg_ss00.png" "$_dir/q"
}

# 1. Empty pool: after install the dest alone remains, nothing is quarantined.
mkscenario "$BASE/empty"
install_then_quarantine "$BASE/empty"
assert_pool "empty pool" "$BASE/empty/pool" "$BASE/empty/q"

# 2. Only bg_ss00.png: the owned file stays, nothing is quarantined.
mkscenario "$BASE/only-dest"
: > "$BASE/only-dest/pool/bg_ss00.png"
install_then_quarantine "$BASE/only-dest"
assert_pool "only bg_ss00.png" "$BASE/only-dest/pool" "$BASE/only-dest/q"

# 3. Only a legacy file, then the install: legacy is quarantined, dest survives.
mkscenario "$BASE/only-legacy"
: > "$BASE/only-legacy/pool/bg_large_ss00.png"
install_then_quarantine "$BASE/only-legacy"
assert_pool "only bg_large_ss00.png" "$BASE/only-legacy/pool" "$BASE/only-legacy/q" "bg_large_ss00.png"

# 4. Dest + legacy: legacy quarantined, dest is the only file left.
mkscenario "$BASE/dest-legacy"
: > "$BASE/dest-legacy/pool/bg_ss00.png"
: > "$BASE/dest-legacy/pool/bg_large_ss00.png"
install_then_quarantine "$BASE/dest-legacy"
assert_pool "bg_ss00.png + bg_large_ss00.png" "$BASE/dest-legacy/pool" "$BASE/dest-legacy/q" "bg_large_ss00.png"

# 5. Dest + another final-name file: the other one is quarantined.
mkscenario "$BASE/dest-ss01"
: > "$BASE/dest-ss01/pool/bg_ss00.png"
: > "$BASE/dest-ss01/pool/bg_ss01.png"
install_then_quarantine "$BASE/dest-ss01"
assert_pool "bg_ss00.png + bg_ss01.png" "$BASE/dest-ss01/pool" "$BASE/dest-ss01/q" "bg_ss01.png"

# 6. Dest + the linkss sample file: the sample is quarantined.
mkscenario "$BASE/dest-sample"
: > "$BASE/dest-sample/pool/bg_ss00.png"
: > "$BASE/dest-sample/pool/00_you_can_delete_me-kv.png"
install_then_quarantine "$BASE/dest-sample"
assert_pool "bg_ss00.png + sample" "$BASE/dest-sample/pool" "$BASE/dest-sample/q" "00_you_can_delete_me-kv.png"

# 7. Dest + several extras: all extras are quarantined, dest alone remains.
mkscenario "$BASE/multi"
: > "$BASE/multi/pool/bg_ss00.png"
: > "$BASE/multi/pool/bg_large_ss00.png"
: > "$BASE/multi/pool/bg_ss01.png"
: > "$BASE/multi/pool/00_you_can_delete_me-kv.png"
install_then_quarantine "$BASE/multi"
assert_pool "multiple extras" "$BASE/multi/pool" "$BASE/multi/q" \
  "bg_large_ss00.png" "bg_ss01.png" "00_you_can_delete_me-kv.png"

# 8. Explicit negative self-check: a pool where the dest and several extras are
#    present. If the helper ever moved the dest, this case would find zero (or a
#    non-bg_ss00.png) pool file and fail.
mkscenario "$BASE/dest-must-survive"
: > "$BASE/dest-must-survive/pool/bg_ss00.png"
: > "$BASE/dest-must-survive/pool/bg_ss07.png"
: > "$BASE/dest-must-survive/pool/bg_ss99.png"
install_then_quarantine "$BASE/dest-must-survive"
assert_pool "dest must survive (negative self-check)" "$BASE/dest-must-survive/pool" "$BASE/dest-must-survive/q" \
  "bg_ss07.png" "bg_ss99.png"

rm -rf "$BASE"

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS pool test case(s) failed"
  exit 1
fi
echo "all pool tests passed"
exit 0
