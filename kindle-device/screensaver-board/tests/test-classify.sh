#!/bin/sh
#
# test-classify.sh - HOST-ONLY tests for bin/lib-payload.sh.
#
# This file is never deployed to the Kindle. It exercises the classifier that
# turns a non-PNG board download into a human-readable reason, including the
# host bot/JS challenge case that broke the Kindle refresh.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/../bin/lib-payload.sh"
FAILS=0

if [ ! -f "$LIB" ]; then
  echo "FAIL missing $LIB"
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

TMP=$(mktemp -d 2>/dev/null) || { echo "FAIL could not create a temp dir"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

check() {
  _name="$1"
  _file="$2"
  _want="$3"
  _got=$(classify_payload "$_file" 2>&1)
  case "$_got" in
    *"$_want"*) echo "PASS $_name" ;;
    *)
      echo "FAIL $_name"
      echo "  wanted substring: $_want"
      echo "  got:              $_got"
      FAILS=$((FAILS + 1))
      ;;
  esac
}

# A host bot/JS challenge page (the exact failure mode that broke the Kindle).
printf '%s\n' '<!DOCTYPE html>' '<html><head><title>One moment, please...</title></head></html>' > "$TMP/challenge.html"
check "challenge page detected" "$TMP/challenge.html" "challenge"

# Same, but <title> carries attributes: the title regex must still match.
printf '%s' '<!DOCTYPE html><html><head><title lang="en">Just a moment</title></head></html>' > "$TMP/challenge-attr.html"
check "challenge page with title attributes" "$TMP/challenge-attr.html" "challenge"

# A plain HTML error page must be reported as HTML, not as a challenge.
printf '%s' '<html><head><title>Oops</title></head></html>' > "$TMP/error.html"
check "generic html page" "$TMP/error.html" "HTML page"

# A UTF-8 BOM and leading whitespace before the doctype must not defeat the HTML check.
printf '\357\273\277\n  <!DOCTYPE html><html><head><title>Hi</title></head></html>' > "$TMP/bom.html"
check "BOM/leading whitespace html" "$TMP/bom.html" "HTML page"

# A non-HTML binary must be reported as non-PNG (with its first bytes).
printf 'GIF89a....' > "$TMP/fake.gif"
check "non-png binary" "$TMP/fake.gif" "not a PNG"

# An empty download must say so.
: > "$TMP/empty.bin"
check "empty download" "$TMP/empty.bin" "empty"

echo ""
if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS classify check(s) failed"
  exit 1
fi
echo "all classify tests passed"
exit 0
