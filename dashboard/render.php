<?php
declare(strict_types=1);

require __DIR__ . '/lib.php';

/**
 * CLI entry point: render the board once and exit.
 *
 * Usage:
 *   php render.php [output.png] [HH:MM]
 *
 * The optional HH:MM argument overrides "now" (today at HH:MM) so the
 * next-prayer and countdown logic can be exercised at any hour.
 *
 * Exits non-zero WITHOUT touching the output file when data is unusable,
 * so a stale-but-good board is never replaced by an error screen.
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("CLI only\n");
}

$cfg = pw_config();
date_default_timezone_set($cfg['timezone']);

$out = $argv[1] ?? ($cfg['out_dir'] . '/board.png');

$now = new DateTimeImmutable('now');
if (isset($argv[2]) && preg_match('/^(\d{1,2}):(\d{2})$/', $argv[2], $m) === 1) {
    $now = $now->setTime((int) $m[1], (int) $m[2], 0);
}

try {
    $result = pw_render_board($cfg, $out, $now);
} catch (Throwable $e) {
    fwrite(STDERR, '[render] ' . $e->getMessage() . "\n");
    exit(1);
}

$next = $result['next'];

printf(
    "[render] ok %dx%d -> %s | next=%s %s (%s) | %s\n",
    (int) $cfg['width'],
    (int) $cfg['height'],
    $out,
    $next['label'] ?? 'n/a',
    $next['time'] ?? '--:--',
    $next !== null ? pw_countdown($now, $next['at']) : 'n/a',
    $now->format('d-M-Y H:i')
);
