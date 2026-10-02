#!/bin/sh
#
# run.sh - HOST-ONLY test runner for the screensaver-board bundle.
#
# This file is never deployed to the Kindle. It syntax-checks every shell script
# in bin/ and documents/, validates menu.json when python3 is available, and runs
# the pool-helper tests.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
FAILS=0

echo "== sh -n on bin/*.sh =="
for f in "$ROOT"/bin/*.sh; do
  [ -e "$f" ] || continue
  if _out=$(sh -n "$f" 2>&1); then
    echo "OK   sh -n ${f##*/}"
  else
    echo "FAIL sh -n ${f##*/}"
    echo "$_out"
    FAILS=$((FAILS + 1))
  fi
done

echo "== sh -n on documents/*.sh =="
for f in "$ROOT"/documents/*.sh; do
  [ -e "$f" ] || continue
  if _out=$(sh -n "$f" 2>&1); then
    echo "OK   sh -n ${f##*/}"
  else
    echo "FAIL sh -n ${f##*/}"
    echo "$_out"
    FAILS=$((FAILS + 1))
  fi
done

echo "== menu.json =="
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$ROOT/menu.json"; then
    echo "OK   menu.json is valid JSON"
  else
    echo "FAIL menu.json is not valid JSON"
    FAILS=$((FAILS + 1))
  fi
else
  echo "SKIP python3 not available - menu.json not validated"
fi

echo "== pool tests =="
if sh "$HERE/test-pool.sh"; then
  echo "OK   test-pool.sh"
else
  echo "FAIL test-pool.sh"
  FAILS=$((FAILS + 1))
fi

echo ""
if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS check(s) failed"
  exit 1
fi
echo "all checks passed"
exit 0
