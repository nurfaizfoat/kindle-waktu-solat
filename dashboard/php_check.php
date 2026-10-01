<?php
/**
 * Temporary capability check for the Kindle waktu-solat dashboard.
 *
 * Usage: upload to public_html, open it in a browser, copy the JSON output,
 * then DELETE this file from the server.
 *
 * Reports only environment capabilities and one outbound fetch test.
 * No secrets, no phpinfo() dump, no writes outside a throwaway PNG.
 */

header('Content-Type: application/json; charset=utf-8');

$report = [
    'php_version'          => PHP_VERSION,
    'sapi'                 => PHP_SAPI,
    'gd_loaded'            => extension_loaded('gd'),
    'gd_freetype'          => null,
    'gd_png'               => null,
    'gd_webp'              => null,
    'imagick_loaded'       => extension_loaded('imagick'),
    'curl_loaded'          => extension_loaded('curl'),
    'allow_url_fopen'      => (bool) ini_get('allow_url_fopen'),
    'memory_limit'         => ini_get('memory_limit'),
    'max_execution_time'   => ini_get('max_execution_time'),
    'disable_functions'    => ini_get('disable_functions'),
    'upload_dir_writable'  => is_writable(__DIR__),
    'png_write_test'       => 'not attempted',
    'jakim_fetch'          => 'not attempted',
];

if ($report['gd_loaded']) {
    $info = gd_info();
    $report['gd_freetype'] = isset($info['FreeType Support']) ? (bool) $info['FreeType Support'] : null;
    $report['gd_png']      = isset($info['PNG Support']) ? (bool) $info['PNG Support'] : null;
    $report['gd_webp']     = isset($info['WebP Support']) ? (bool) $info['WebP Support'] : null;

    // Prove GD can allocate and write a PNG file next to this script.
    $im = imagecreatetruecolor(320, 120);
    imagefilledrectangle($im, 0, 0, 319, 119, imagecolorallocate($im, 255, 255, 255));
    imagestring($im, 5, 12, 50, 'GD PNG OK', imagecolorallocate($im, 0, 0, 0));
    $path = __DIR__ . '/_gd_test.png';
    $report['png_write_test'] = imagepng($im, $path) ? 'ok: _gd_test.png' : 'failed';
    imagedestroy($im);
}

$url = 'https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=today&zone=WLY01';

if ($report['curl_loaded']) {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $body = curl_exec($ch);
    $err  = curl_error($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $report['jakim_fetch'] = ($body === false)
        ? 'curl error: ' . $err
        : 'http ' . $code . ', ' . strlen($body) . ' bytes, starts: ' . substr($body, 0, 60);
} elseif ($report['allow_url_fopen']) {
    $ctx  = stream_context_create(['http' => ['timeout' => 15]]);
    $body = @file_get_contents($url, false, $ctx);
    $report['jakim_fetch'] = ($body === false)
        ? 'file_get_contents failed (may be blocked)'
        : 'ok, ' . strlen($body) . ' bytes, starts: ' . substr($body, 0, 60);
} else {
    $report['jakim_fetch'] = 'no curl and allow_url_fopen is off';
}

echo json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
