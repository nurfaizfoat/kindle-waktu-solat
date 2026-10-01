<?php
declare(strict_types=1);

require __DIR__ . '/lib.php';

/**
 * CLI entry point: refresh the yearly JAKIM snapshot for the configured zone.
 *
 * JAKIM only serves the CURRENT year, so this must run on a schedule to
 * keep a full year of records on disk. Optional when board.php is used,
 * which refreshes the snapshot itself at most once a day.
 *
 * Usage:
 *   php fetch.php          # current year
 *   php fetch.php 2027     # explicit year
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI only\n");
}

$cfg  = pw_config();
$year = isset($argv[1]) ? (int) $argv[1] : (int) date('Y');

try {
    $count = pw_fetch_snapshot($cfg, $year);
} catch (Throwable $e) {
    fwrite(STDERR, '[fetch] ' . $e->getMessage() . "\n");
    exit(1);
}

printf(
    "[fetch] ok zone=%s year=%d records=%d -> %s\n",
    $cfg['zone'],
    $year,
    $count,
    pw_snapshot_path($cfg['zone'], $year)
);
