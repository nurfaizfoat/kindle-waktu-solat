#!/bin/sh
#
# lib-pool.sh - shared, SOURCED helper for pruning the linkss screensaver pool.
#
# This file is NOT executed directly: it is sourced with `. "$BIN/lib-pool.sh"`
# by set-screensaver.sh. It assumes a log() function is already defined by the
# caller. It never deletes anything: extras are MOVED to a quarantine directory
# so they can be recovered by hand.
#
# pool_quarantine_extras <ssdir> <dest> <qdir>
#   For every *.png directly in <ssdir> other than <dest>, move it into <qdir>.
#   If a file of the same name already exists in <qdir>, suffix ".<pid>" so the
#   existing quarantined copy is not overwritten. Each move is logged. A failed
#   move is logged as a WARNING that the pool may still cycle.
#
# The caller must ensure <qdir> is on the same mounted userstore so the moves are
# cheap renames rather than copies.

pool_quarantine_extras() {
  _ssdir="$1"
  _dest="$2"
  _qdir="$3"

  [ -d "$_ssdir" ] || return 0

  if ! mkdir -p "$_qdir" 2>/dev/null; then
    log "WARNING: could not create quarantine dir $_qdir; the pool may still cycle."
    return 1
  fi

  for _pf in "$_ssdir"/*.png; do
    [ -e "$_pf" ] || continue
    [ "$_pf" = "$_dest" ] && continue

    _pbase=${_pf##*/}
    _ptarget="$_qdir/$_pbase"
    if [ -e "$_ptarget" ]; then
      _ptarget="$_qdir/$_pbase.$$"
    fi

    if mv "$_pf" "$_ptarget" 2>/dev/null; then
      log "quarantined extra screensaver file: $_pf -> $_ptarget (moved, not deleted)"
    else
      log "WARNING: could not move $_pf to $_qdir; the pool may still cycle."
    fi
  done

  return 0
}
