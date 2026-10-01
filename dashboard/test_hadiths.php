<?php
declare(strict_types=1);

// Local-only: php dashboard/test_hadiths.php [preview-directory]
require __DIR__ . '/lib.php';

function hadith_check(bool $ok, string $message): void
{
    if (!$ok) {
        throw new RuntimeException($message);
    }
}

$cfg = pw_config();
$tz = new DateTimeZone($cfg['timezone']);
$start = new DateTimeImmutable('2026-09-30 00:00:00', $tz);
$entries = pw_hadiths();
hadith_check(count($entries) === 50, 'Expected the curated 50-entry collection');
$seen = [];
for ($day = 0; $day < 50; $day++) {
    $date = $start->modify("+$day days");
    $entry = pw_daily_hadith($date);
    hadith_check(!isset($seen[$entry['id']]), "Repeated entry before day 51: {$entry['id']}");
    $seen[$entry['id']] = true;
    hadith_check($entry === pw_daily_hadith($date->setTime(23, 59, 59)),
        'Selection changed within a local day');
    hadith_check($entry === pw_daily_hadith($date->setTimezone(new DateTimeZone('UTC'))),
        'Selection depends on caller timezone');
}
hadith_check(pw_daily_hadith($start->modify('+50 days')) === $entries[0],
    'Day 51 must restart the cycle');
hadith_check(pw_daily_hadith($start->modify('-1 second')) === $entries[49],
    'Negative dates or local midnight are incorrect');
hadith_check(pw_daily_hadith($start->modify('-50 days')) === $entries[0],
    'Negative full-cycle offset is incorrect');
foreach (['2026-12-31', '2028-02-28', '2028-02-29'] as $boundary) {
    $date = new DateTimeImmutable($boundary, $tz);
    hadith_check(pw_daily_hadith($date->setTime(23, 59, 59)) !==
        pw_daily_hadith($date->modify('+1 day')), "Rotation failed at $boundary");
}

// Validate failure handling without touching the real collection.
$validDocument = json_decode(file_get_contents(__DIR__ . '/data/hadiths-ms.json'), true, 512, JSON_THROW_ON_ERROR);
$fixtures = ['invalid JSON' => '{', 'non-object' => 'null'];
foreach (['empty', 'not-list', 'not-entry', 'missing-text', 'wrong-source',
    'wrong-url', 'wrong-collection', 'duplicate-id', 'duplicate-text', 'multiline'] as $case) {
    $bad = $validDocument;
    switch ($case) {
        case 'empty': $bad['hadiths'] = []; break;
        case 'not-list': $bad['hadiths'] = ['named' => $entries[0]]; break;
        case 'not-entry': $bad['hadiths'][0] = 'invalid'; break;
        case 'missing-text': unset($bad['hadiths'][0]['text']); break;
        case 'wrong-source': $bad['hadiths'][0]['source'] = 'Sahih Muslim · 6018'; break;
        case 'wrong-url': $bad['hadiths'][0]['url'] = 'https://sunnah.com/bukhari:1'; break;
        case 'wrong-collection': $bad['hadiths'][0]['id'] = 'other-6018'; break;
        case 'duplicate-id': $bad['hadiths'][] = $entries[0]; break;
        case 'duplicate-text': $bad['hadiths'][1]['text'] = $entries[0]['text']; break;
        case 'multiline': $bad['hadiths'][0]['text'] .= "\nAnother line"; break;
    }
    $fixtures[$case] = json_encode($bad, JSON_THROW_ON_ERROR);
}
$fixturePath = tempnam(sys_get_temp_dir(), 'kindle-hadith-');
hadith_check($fixturePath !== false, 'Cannot create test fixture');
try {
    foreach ($fixtures as $name => $json) {
        file_put_contents($fixturePath, $json);
        $rejected = false;
        try {
            pw_hadiths($fixturePath);
        } catch (RuntimeException $e) {
            $rejected = true;
        }
        hadith_check($rejected, "Accepted malformed collection: $name");
    }
    $rejected = false;
    try {
        pw_hadiths($fixturePath . '.missing');
    } catch (RuntimeException $e) {
        $rejected = true;
    }
    hadith_check($rejected, 'Missing JSON must fail clearly');
} finally {
    unlink($fixturePath);
}

$outDir = $argv[1] ?? sys_get_temp_dir() . '/kindle-hadith-previews';
if (!is_dir($outDir)) {
    hadith_check(mkdir($outDir, 0755, true), 'Cannot create preview directory');
}
$font = $cfg['font_dir'] . '/dogicapixel.ttf';
$heroX = (int) round($cfg['width'] * 0.45) + 48;
$heroWidth = $cfg['width'] - $heroX - 48;
foreach ($entries as $day => $entry) {
    $lines = pw_hadith_lines($entry['text'], $font, 22, $heroWidth);
    hadith_check(implode(' ', $lines) === $entry['text'], "Text lost: {$entry['id']}");
    foreach ($lines as $line) {
        hadith_check(pw_text_width(22, $font, $line) <= $heroWidth,
            "Text overflows: {$entry['id']}");
    }

    // A tighter gap than the current hero/footer leaves: inspect the raster,
    // so a long quote or attribution cannot silently clip the adjacent UI.
    $probe = imagecreatetruecolor($cfg['width'], $cfg['height']);
    $white = imagecolorallocate($probe, 255, 255, 255);
    $black = imagecolorallocate($probe, 0, 0, 0);
    imagefill($probe, 0, 0, $white);
    pw_draw_hadith($probe, $entry, $font, $heroX, $heroWidth, 450, 1260, $black, $black);
    $ink = 0;
    for ($y = 0; $y < $cfg['height']; $y++) {
        for ($x = 0; $x < $cfg['width']; $x++) {
            if (imagecolorat($probe, $x, $y) === $white) {
                continue;
            }
            $ink++;
            hadith_check($x >= $heroX && $x <= $heroX + $heroWidth && $y >= 498 && $y < 1212,
                "Hadith exceeds reserved space: {$entry['id']} at $x,$y");
        }
    }
    hadith_check($ink > 100, "Empty hadith raster: {$entry['id']}");
    imagedestroy($probe);

    $date = $start->modify("+$day days")->setTime(10, 10);
    $path = $outDir . '/' . sprintf('%02d', $day + 1) . '-' . $entry['id'] . '.png';
    pw_render_board($cfg, $path, $date);
    $size = getimagesize($path);
    hadith_check($size !== false && $size[0] === 1072 && $size[1] === 1448,
        "Invalid rendered board: {$entry['id']}");
}
echo "PASS 50 unique hadiths, full cycle, KL midnight, leap/year boundaries, invalid JSON, and 50 rendered layouts\n";
echo "Previews: $outDir\n";
