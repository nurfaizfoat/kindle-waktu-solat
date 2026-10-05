#!/bin/sh
#
# lib-payload.sh - SOURCED helper: describe a non-PNG board download.
#
# WHY THIS EXISTS
#   When the board URL is up but does not return a PNG, a bare "fetch failed"
#   gives the user nothing to act on. This helper inspects the downloaded bytes
#   and prints one human-readable sentence that names the likely cause, in
#   particular a host bot/JS challenge (an HTML interstitial the Kindle cannot
#   solve) versus a plain network failure.
#
#   Kept in its own file, like lib-pool.sh, so the host-only test runner can
#   exercise it without a Kindle.
#
# classify_payload <file>: print the description. The caller must have already
#   confirmed the file is not a valid PNG. Reads at most the first 1 KiB.

classify_payload() {
  _cp_f="$1"

  # Sniff the first 1 KiB, lower-cased, so leading whitespace or a UTF-8 BOM
  # before "<!doctype html>" does not defeat the HTML check.
  _cp_head=$(dd if="$_cp_f" bs=1 count=1024 2>/dev/null | tr 'A-Z' 'a-z')

  case "$_cp_head" in
    *"<!doctype html"*|*"<html"*|*"<head"*)
      _cp_title=$(awk 'BEGIN{RS="<"} {t=tolower($0); if (t ~ /^title[^>]*>/) {sub(/^title[^>]*>/,""); gsub(/<.*/,""); gsub(/[\r\n\t]+/," "); gsub(/ +/," "); print; exit}}' "$_cp_f" 2>/dev/null)
      [ -n "$_cp_title" ] || _cp_title="(no <title>)"
      _cp_lc=$(printf '%s' "$_cp_title" | tr 'A-Z' 'a-z')
      case "$_cp_lc" in
        *"one moment"*|*"just a moment"*|*challenge*|*cloudflare*|*attention*|*verify*)
          echo "the server returned an HTML bot/JS challenge, not a PNG (title: '$_cp_title')" ;;
        *)
          echo "the server returned an HTML page, not a PNG (title: '$_cp_title')" ;;
      esac
      ;;
    "")
      echo "the download was empty" ;;
    *)
      _cp_sig=$(dd if="$_cp_f" bs=1 count=8 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
      echo "the download is not a PNG (first bytes: ${_cp_sig:-unknown})" ;;
  esac
}
