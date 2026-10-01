<?php
declare(strict_types=1);

require __DIR__ . '/lib.php';

/**
 * Web entry point: render the board on demand and serve it as a PNG.
 *
 * Point the Kindle browser here. No cron job and no PHP CLI path are
 * required, which matters on shared hosts where shell access is disabled.
 *
 * Resilience:
 *  - A recent render is reused for a short window instead of re-rendering
 *    on every refresh.
 *  - If rendering fails, the last good PNG is served rather than an error,
 *    so a transient JAKIM outage never blanks the device.
 *  - The yearly snapshot is refreshed at most once a day, so refreshing
 *    every few minutes does not hammer JAKIM.
 */

$cfg = pw_config();
date_default_timezone_set($cfg['timezone']);

$out      = $cfg['out_dir'] . '/board.png';
$cacheTtl = 60;   // seconds a rendered board is reused
$now      = new DateTimeImmutable('now');

$fresh = is_file($out) && (time() - (int) filemtime($out)) < $cacheTtl;

header('Content-Type: image/png');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

if (!$fresh) {
    try {
        $year     = (int) $now->format('Y');
        $snapshot = pw_snapshot_path($cfg['zone'], $year);

        if (!is_file($snapshot) || (time() - (int) filemtime($snapshot)) > 86400) {
            pw_fetch_snapshot($cfg, $year);
        }

        pw_render_board($cfg, $out, $now);
    } catch (Throwable $e) {
        // Log and fall through: a stale board beats no board.
        error_log('[board] ' . $e->getMessage());
    }
}

if (is_file($out)) {
    header('Content-Length: ' . (string) filesize($out));
    readfile($out);
    exit;
}

http_response_code(500);
header('Content-Type: text/plain; charset=utf-8');
echo "Board unavailable and no cached render exists.\n";
