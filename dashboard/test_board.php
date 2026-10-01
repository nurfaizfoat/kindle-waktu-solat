<?php
declare(strict_types=1);

// Local-only contract test: php dashboard/test_board.php [/tmp/opencode]
require __DIR__ . '/lib.php';

function check(bool $ok, string $message): void
{
    if (!$ok) {
        throw new RuntimeException($message);
    }
}

/** Palette channel at a pixel, after the renderer's 16-gray conversion. */
function gray_at($image, int $x, int $y): int
{
    $color = imagecolorsforindex($image, imagecolorat($image, $x, $y));
    return (int) $color['red'];
}

/** Darkest pixel in a known text-only region (avoids OCR dependencies). */
function darkest($image, int $x1, int $y1, int $x2, int $y2): int
{
    $min = 255;
    for ($y = $y1; $y <= $y2; $y++) {
        for ($x = $x1; $x <= $x2; $x++) {
            $min = min($min, gray_at($image, $x, $y));
        }
    }
    return $min;
}

/** Bottommost visible pixel in a bounded region. */
function ink_bottom($image, int $x1, int $y1, int $x2, int $y2, int $threshold, bool $lighter = false): int
{
    for ($y = $y2; $y >= $y1; $y--) {
        for ($x = $x1; $x <= $x2; $x++) {
            $gray = gray_at($image, $x, $y);
            if ($lighter ? $gray >= $threshold : $gray <= $threshold) {
                return $y;
            }
        }
    }
    throw new RuntimeException('No ink in expected region');
}

/** Number of dark pixels in a rendered clock crop. */
function ink_count($image, int $x1, int $y1, int $x2, int $y2): int
{
    $count = 0;
    for ($y = $y1; $y <= $y2; $y++) {
        for ($x = $x1; $x <= $x2; $x++) {
            if (gray_at($image, $x, $y) < 128) {
                $count++;
            }
        }
    }
    return $count;
}

/** Compare a single untouched text box against a specified font raster. */
function check_text_raster($board, string $font, float $size, string $text,
    int $x, int $y, bool $onBlack, string $message): void
{
    $w = (int) ceil(pw_text_width($size, $font, $text));
    $h = (int) ceil(pw_text_height($size, $font, $text));
    $probe = imagecreatetruecolor($w + 2, $h + 2);
    $white = imagecolorallocate($probe, 255, 255, 255);
    $black = imagecolorallocate($probe, 0, 0, 0);
    imagefilledrectangle($probe, 0, 0, $w + 1, $h + 1, $onBlack ? $black : $white);
    pw_text($probe, $size, $font, 0, 0, $onBlack ? $white : $black, $text);
    $different = 0;
    for ($py = 0; $py < $h; $py++) {
        for ($px = 0; $px < $w; $px++) {
            // The board's 16-step palette can place a mid-gray edge on the
            // opposite side of 128 from GD's original anti-alias sample.
            if ((gray_at($probe, $px, $py) >= 100) !== (gray_at($board, $x + $px, $y + $py) >= 100)) {
                $different++;
            }
        }
    }
    imagedestroy($probe);
    check($different < $w * $h * 0.01, "$message ($different differing pixels)");
}

/** Compare actual rasterized glyphs, not just advances (which can match). */
function glyph_signature(string $font, string $glyph): string
{
    $im = imagecreatetruecolor(100, 100);
    $black = imagecolorallocate($im, 0, 0, 0);
    $white = imagecolorallocate($im, 255, 255, 255);
    imagefill($im, 0, 0, $white);
    imagettftext($im, 32, 0, 10, 55, $black, $font, $glyph);
    $pixels = '';
    for ($y = 0; $y < 100; $y++) {
        for ($x = 0; $x < 100; $x++) {
            $pixels .= imagecolorat($im, $x, $y) === $white ? '0' : '1';
        }
    }
    imagedestroy($im);
    return hash('sha256', $pixels);
}

$cfg = pw_config();
date_default_timezone_set($cfg['timezone']);
$font = $cfg['font_dir'] . '/dogicapixel.ttf';
$boldFont = $cfg['font_dir'] . '/dogicapixelbold.ttf';
check(is_readable($font) && is_readable($cfg['font_dir'] . '/dogica_pixel_license.txt'),
    'Dogica Pixel font or its own license missing');
check(is_readable($boldFont), 'Original Dogica Pixel Bold missing');
check(glyph_signature($font, '5') !== glyph_signature($font, 'S'), '5 must differ from S');
check(glyph_signature($font, '5') !== glyph_signature($font, '6'), '5 must differ from 6');
check(glyph_signature($font, 'a') !== glyph_signature($font, 'A'), 'lowercase must be distinct');
check(glyph_signature($font, 'PM') !== glyph_signature($boldFont, 'PM'),
    'AM/PM raster comparison cannot distinguish regular from bold');
check(glyph_signature($font, 'Isyak') !== glyph_signature($boldFont, 'Isyak'),
    'selected Isyak raster comparison cannot distinguish regular from bold');
$doc = pw_load_document($cfg['zone'], 2026);
check($doc !== null, 'Missing local 2026 JAKIM snapshot');
$index = pw_index($doc);
$split = (int) round($cfg['width'] * 0.45);
$timeRight = $split - 36;
$heroX = $split + 48;
$heroWidth = $cfg['width'] - $heroX - 48;
$captionSize = pw_fit(26, $font, 'SOLAT SETERUSNYA', $heroWidth, 14);
$hadithMorning = pw_daily_hadith(new DateTimeImmutable('2026-09-30 00:00'));
check($hadithMorning['source'] === 'Sahih al-Bukhari · 6018', 'Mockup day hadith changed');
check($hadithMorning === pw_daily_hadith(new DateTimeImmutable('2026-09-30 23:59')),
    'Hadith must remain stable throughout the day');
check($hadithMorning !== pw_daily_hadith(new DateTimeImmutable('2026-10-01 00:00')),
    'Hadith must rotate at local midnight');
check($hadithMorning === pw_daily_hadith(new DateTimeImmutable('2026-09-29 16:00 UTC')),
    'Hadith selection must use Kuala Lumpur date');
check(pw_daily_hadith(new DateTimeImmutable('2026-12-31 23:59')) !==
    pw_daily_hadith(new DateTimeImmutable('2027-01-01 00:00')), 'Year boundary must rotate');
foreach (pw_hadiths() as $hadith) {
    $lines = pw_hadith_lines($hadith['text'], $font, 22, $heroWidth);
    check(implode(' ', $lines) === $hadith['text'], 'Wrapping dropped hadith text');
    foreach ($lines as $line) {
        check(pw_text_width(22, $font, $line) <= $heroWidth, 'Hadith line overflows');
    }
}
$outputDir = $argv[1] ?? sys_get_temp_dir();
check(is_dir($outputDir) && is_writable($outputDir), 'Preview directory not writable');

$cases = [
    'normal' => ['2026-09-29 12:00', 'SELASA, 29 SEPT', 'Zohor', false],
    'friday' => ['2026-10-02 11:00', 'JUMAAT, 02 OKT', 'Jumaat', false],
    'ramadan' => ['2026-02-28 04:00', 'SABTU, 28 FEB', 'Subuh', true],
    'october' => ['2026-10-01 12:00', 'KHAMIS, 01 OKT', 'Zohor', false],
    'year-end-friday' => ['2026-12-25 11:00', 'JUMAAT, 25 DIS', 'Jumaat', false],
    'year-end' => ['2026-12-31 12:00', 'KHAMIS, 31 DIS', 'Zohor', false],
    'maghrib-highlight' => ['2026-09-29 17:00', 'SELASA, 29 SEPT', 'Maghrib', false],
    'last-row-highlight' => ['2026-09-29 19:30', 'SELASA, 29 SEPT', 'Isyak', false],
    'after-isyak-with-tomorrow' => ['2026-12-30 21:00', 'RABU, 30 DIS', 'Subuh', false],
    'year-end-after-isyak' => ['2026-12-31 20:31', 'KHAMIS, 31 DIS', null, false],
];

// Literal snapshot fixtures: never obtain expected glyphs from pw_time_parts()
// or pw_time_12h(), since the renderer uses those same formatters.
$timeFixtures = [
    'normal' => ['13:06', '1:06', 'PM', '1:06 PM', '13:06:00'],
    'friday' => ['13:05', '1:05', 'PM', '1:05 PM', '13:05:00'],
    'ramadan' => ['06:17', '6:17', 'AM', '6:17 AM', '06:17:00'],
    'october' => ['13:06', '1:06', 'PM', '1:06 PM', '13:06:00'],
    'year-end-friday' => ['13:16', '1:16', 'PM', '1:16 PM', '13:16:00'],
    'year-end' => ['13:19', '1:19', 'PM', '1:19 PM', '13:19:00'],
    'maghrib-highlight' => ['19:08', '7:08', 'PM', '7:08 PM', '19:08:00'],
    'last-row-highlight' => ['20:17', '8:17', 'PM', '8:17 PM', '20:17:00'],
    // After Isyak, tomorrow's Subuh is the hero; no row today is selected.
    'after-isyak-with-tomorrow' => ['06:06', '6:06', 'AM', null, '06:06:00'],
];

foreach ($cases as $slug => [$date, $expectedDate, $expectedNext, $expectImsak]) {
    $now = new DateTimeImmutable($date);
    $today = pw_record($index, $now);
    check($today !== null, "$slug: no snapshot record");
    check(pw_board_date($now) === $expectedDate, "$slug: date changed");
    check(pw_text_width($captionSize, $font, $expectedDate) <= $split - 56,
        "$slug: date overflows left panel");
    $next = pw_next_prayer($index, $now);
    check(($next['label'] ?? null) === $expectedNext, "$slug: next prayer changed");
    if ($next !== null) {
        [$expected24h, $clock, $meridiem, $selectedTime, $rawTime] = $timeFixtures[$slug];
        $expectedRecord = $next['tomorrow'] ? pw_record($index, $now->modify('+1 day')) : $today;
        check($next['time'] === $expected24h && ($expectedRecord[$next['key']] ?? null) === $rawTime,
            "$slug: published fixture time changed");
    }
    check(pw_tomorrow_unavailable($index, $now) === ($expectedNext === null),
        "$slug: tomorrow availability changed");
    if ($slug === 'after-isyak-with-tomorrow') {
        check($next['tomorrow'] === true && $next['at']->format('Y-m-d H:i') === '2026-12-31 06:06',
            'Dec 30 rollover must use the published Dec 31 Subuh');
    }
    $labels = array_column(pw_display_rows($now, $today), 'label');
    check(in_array('Imsak', $labels, true) === $expectImsak, "$slug: Imsak visibility changed");
    check(!in_array('Syuruk', $labels, true) && !in_array('Dhuha', $labels, true), "$slug: non-fard row visible");
    check(in_array(pw_is_friday($now) ? 'Jumaat' : 'Zohor', $labels, true), "$slug: Friday row changed");

    $footer = pw_ramadan_footer($today, pw_next_ramadan($doc, $now), $now);
    check($footer !== null, "$slug: footer missing");
    if ($expectImsak) {
        check($footer[0] === 'Ramadhan hari ke-10' && $footer[1] === '· Puasa hari ini',
            'Ramadan in-progress footer changed');
    } else {
        check((bool) preg_match('/^Ramadhan [0-9]+ hari lagi\.$/', $footer[0]), "$slug: old countdown wording");
        check(str_starts_with($footer[1], '1 Ramadhan 1448 · ~8 Feb 2027'), "$slug: expected first Ramadan missing");
    }

    [$rowSize, $timeSize] = pw_timeline_sizes(pw_display_rows($now, $today), $today, $font, 88, $timeRight);
    $card = pw_highlight_geometry(88, $timeRight, 750);
    check($card['left'] === 74 && $card['right'] === $split - 22 && $card['right'] < $split,
        "$slug: fixed card bounds outside black panel");
    check(88 - $card['left'] === 14 && $card['right'] - $timeRight === 14
        && $split - $card['right'] === 22,
        "$slug: unequal card padding");

    $out = $outputDir . '/kindle-contract-' . $slug . '.png';
    pw_render_board($cfg, $out, $now);
    $im = imagecreatefrompng($out);
    check($im !== false && imagesx($im) === 1072 && imagesy($im) === 1448, "$slug: invalid PNG");
    check(gray_at($im, 0, 0) === 0 && gray_at($im, $split, 700) === 0
        && gray_at($im, $split + 1, 700) === 255, "$slug: 45/55 panel boundary changed");
    check_text_raster($im, $font, $captionSize, $expectedDate, 28, 48, true,
        "$slug: date not drawn at shared heading size");
    check_text_raster($im, $font, $captionSize, 'SOLAT SETERUSNYA', $heroX, 48, false,
        "$slug: caption not drawn at shared heading size");
    $captionInk = darkest($im, $split + 48, 48, $split + 400, 90);
    if ($next !== null) {
        $nameSize = pw_fit(76, $font, $next['label'], $heroWidth, 26);
        check_text_raster($im, $font, $nameSize, $next['label'], $heroX, 160, false,
            "$slug: hero prayer name was emboldened");
        $timeY = 160 + pw_text_height($nameSize, $font, $next['label']) + 40;
        $clockSize = pw_fit(96, $boldFont, $clock, $heroWidth - pw_text_width(30, $font, $meridiem) - 22, 40);
        $clockWidth = (int) ceil(pw_text_width($clockSize, $boldFont, $clock));
        $clockHeight = (int) ceil(pw_text_height($clockSize, $boldFont, $clock));
        $heroEnd = $timeY + $clockHeight;
        check_text_raster($im, $boldFont, $clockSize, $clock, $heroX, (int) $timeY, false,
            "$slug: hero clock does not show the literal fixture time");
        $merH = pw_text_height(30, $font, $meridiem);
        check_text_raster($im, $font, 30, $meridiem,
            (int) round($heroX + pw_text_width($clockSize, $boldFont, $clock) + 22),
            (int) round($timeY + $clockHeight - $merH), false,
            "$slug: AM/PM is not regular Dogica Pixel");
    } else {
        $heading = 'Jadual esok';
        $detail = 'belum tersedia';
        $headingSize = pw_fit(62, $font, $heading, $heroWidth, 26);
        $detailY = 160 + pw_text_height($headingSize, $font, $heading) + 26;
        $detailSize = pw_fit(38, $font, $detail, $heroWidth, 18);
        check_text_raster($im, $font, $headingSize, $heading, $heroX, 160, false,
            "$slug: missing tomorrow heading");
        check_text_raster($im, $font, $detailSize, $detail, $heroX, (int) $detailY, false,
            "$slug: missing tomorrow detail");
        check(gray_at($im, $heroX, 340) === 255, "$slug: fabricated clock visible");
        $heroEnd = $detailY + pw_text_height($detailSize, $font, $detail);
    }
    $leftBottom = ink_bottom($im, 75, 1300, $timeRight, 1447, 160, true);
    $ishaLabel = 'Isyak';
    [$rowSize] = pw_timeline_sizes(pw_display_rows($now, $today), $today, $font, 88, $timeRight);
    $ishaTop = (int) round(($cfg['height'] - 38 - 32) - pw_text_height($rowSize, $font, $ishaLabel) / 2);
    if ($next === null || $next['key'] !== 'isha') {
        check_text_raster($im, $font, $rowSize, $ishaLabel, 88, $ishaTop, true,
            "$slug: Isyak timeline label was emboldened");
    }
    $footerLayout = pw_footer_geometry($footer[0], $footer[1], $font, $heroWidth, $leftBottom, $heroEnd);
    $subtitleInk = darkest($im, $heroX, (int) $footerLayout['sub_y'],
        $heroX + 500, $leftBottom + 2);
    check($captionInk >= 51 && $captionInk <= 102, "$slug: caption contrast changed");
    check($subtitleInk >= 51 && $subtitleInk <= 102, "$slug: subtitle contrast changed");

    // Compare the rendered clock against the regular face at the SAME size;
    // only the large time is bold. No dilation/overdraw of the name or rows.
    if ($next !== null) {
        $probe = imagecreatetruecolor($clockWidth + 10, $clockHeight + 10);
        $probeWhite = imagecolorallocate($probe, 255, 255, 255);
        $probeBlack = imagecolorallocate($probe, 0, 0, 0);
        imagefilledrectangle($probe, 0, 0, $clockWidth + 9, $clockHeight + 9, $probeWhite);
        pw_text($probe, $clockSize, $font, 0, 0, $probeBlack, $clock);
        $regularInk = ink_count($probe, 0, 0, $clockWidth - 1, $clockHeight - 1);
        $clockInk = ink_count($im, $heroX, (int) $timeY, $heroX + $clockWidth - 1, (int) $timeY + $clockHeight - 1);
        check($clockInk > $regularInk * 1.08, "$slug: main clock is not visibly bolder than regular Dogica");
        imagefilledrectangle($probe, 0, 0, $clockWidth + 9, $clockHeight + 9, $probeWhite);
        pw_text($probe, $clockSize, $boldFont, 0, 0, $probeBlack, $clock);
        $boldInk = ink_count($probe, 0, 0, $clockWidth - 1, $clockHeight - 1);
        check(abs($clockInk - $boldInk) < $boldInk * 0.04, "$slug: clock does not match genuine bold face ($clockInk vs $boldInk)");
        imagedestroy($probe);
    }

    // At x=76 the rounded card has a long white run; text and marker do not.
    $runs = [];
    $start = null;
    for ($y = 100; $y < 1410; $y++) {
        $white = gray_at($im, 76, $y) === 255;
        if ($white && $start === null) {
            $start = $y;
        } elseif (!$white && $start !== null) {
            if ($y - $start >= 45) {
                $runs[] = [$start, $y - 1];
            }
            $start = null;
        }
    }
    if ($next === null || $next['tomorrow']) {
        check(count($runs) === 0, "$slug: tomorrow/unavailable row was highlighted");
    } else {
        check(count($runs) === 1, "$slug: missing or overlapping highlight cards");
        [$top, $bottom] = $runs[0];
        check($top > 110 && $bottom < 1410, "$slug: card clips date or bottom");
        $cy = (int) (($top + $bottom) / 2);
        $edge = pw_highlight_geometry(88, $timeRight, $cy);
        // Probe the actual PNG, not just helper geometry. The edge strip is
        // outside both glyph boxes; a text-hugging card must fail here.
        check(gray_at($im, $edge['left'] - 1, $cy) === 0
            && gray_at($im, $edge['left'], $cy) === 255,
            "$slug: rendered card left edge shifted");
        check(gray_at($im, $edge['right'], $cy) === 255
            && gray_at($im, $edge['right'] + 1, $cy) === 0,
            "$slug: rendered card shorter than shared time edge");
        check(gray_at($im, $split - 1, $cy) === 0 && gray_at($im, $split + 1, $cy) === 255,
            "$slug: card touches panel boundary");
        check(gray_at($im, $edge['left'], $edge['top']) === 0
            && gray_at($im, $edge['right'], $edge['top']) === 0
            && gray_at($im, 88, $edge['top']) === 255
            && gray_at($im, $edge['left'], $edge['bottom']) === 0
            && gray_at($im, $edge['right'], $edge['bottom']) === 0
            && gray_at($im, 88, $edge['bottom']) === 255,
            "$slug: rendered card corners are not rounded");
        check(gray_at($im, 40, $cy) === 255 && gray_at($im, 60, $cy) === 0,
            "$slug: selected dot or spine gap obscured");
        check($selectedTime !== null, "$slug: selected row fixture missing");
        // At x=76 the rounded corners trim the run symmetrically, leaving
        // its midpoint at the selected row centre for the text-only probe.
        $selectedTimeTop = (int) round($cy - pw_text_height($timeSize, $font, $selectedTime) / 2);
        check_text_raster($im, $font, $timeSize, $selectedTime,
            (int) round($timeRight - pw_text_width($timeSize, $font, $selectedTime)),
            $selectedTimeTop, false, "$slug: selected time is not aligned with other rows");
        if ($next['key'] === 'isha') {
            // The x=76 probe crosses rounded card corners, so its run's
            // midpoint is not the row centre. Isyak maps to tlBottom.
            $cy = $cfg['height'] - 38 - 32;
            $selectedTop = (int) round($cy - pw_text_height($rowSize, $font, 'Isyak') / 2);
            check_text_raster($im, $font, $rowSize, 'Isyak', 88, $selectedTop, false,
                "$slug: selected Isyak label is not regular");
        }
    }
    // Isyak is the last row. Include its white card edge if selected; the
    // footer subtitle's actual ink bottom should track that visual bottom.
    $rightBottom = ink_bottom($im, $heroX, (int) $footerLayout['rule_y'] + 4,
        $cfg['width'] - 48, 1447, 170);
    check(abs($leftBottom - $rightBottom) <= 3, "$slug: subtitle/Isyak bottom mismatch ($rightBottom vs $leftBottom)");
    check($rightBottom < 1447 - 20 && $footerLayout['rule_y'] > $heroEnd + 36,
        "$slug: footer touches board edge or hero");
    check(darkest($im, $heroX, (int) $footerLayout['rule_y'] - 5,
        $cfg['width'] - 48, (int) $footerLayout['rule_y'] + 5) === 0, "$slug: footer divider missing");
    imagedestroy($im);
    print "PASS $slug -> $out\n";
}

// Synthetic published and estimated first-Ramadan dates. The local 2026
// snapshot's real countdown crosses into February 2027, so it cannot exercise
// the other Malay month spellings or the published-date branch on its own.
foreach ([3 => 'Mac', 5 => 'Mei', 8 => 'Ogos', 10 => 'Okt', 12 => 'Dis'] as $month => $name) {
    $first = new DateTimeImmutable(sprintf('2026-%02d-01', $month));
    $now = $first->modify('-1 day')->setTime(12, 0);
    foreach ([false, true] as $estimated) {
        $footer = pw_ramadan_footer(['hijri' => '1448-08-29'], [
            'date' => $first, 'estimated' => $estimated, 'hijri_year' => 1448,
        ], $now);
        $marker = $estimated ? '~' : '';
        check($footer === ['Ramadhan 1 hari lagi.', "1 Ramadhan 1448 · {$marker}1 $name 2026"],
            "$name: published/estimated footer or Malay abbreviation changed");
    }
}
check(pw_iso_key('01-Okt-2026') === '2026-10-01' && pw_iso_key('29-Sep-2026') === '2026-09-29',
    'Malay JAKIM date parsing changed');

// Iterate the calendar, not the snapshot: a missing day and an extra/duplicate
// day can otherwise keep the record count unchanged. DatePeriod handles leap
// years without a hard-coded 365-day assumption.
$year = 2026;
$shortMonths = [1 => 'JAN', 'FEB', 'MAC', 'APR', 'MEI', 'JUN', 'JUL', 'OGOS', 'SEPT', 'OKT', 'NOV', 'DIS'];
$shortDays = [1 => 'ISNIN', 'SELASA', 'RABU', 'KHAMIS', 'JUMAAT', 'SABTU', 'AHAD'];
$days = new DatePeriod(new DateTimeImmutable("$year-01-01 12:00"),
    new DateInterval('P1D'), new DateTimeImmutable(($year + 1) . '-01-01 12:00'));
$checked = 0;
foreach ($days as $day) {
    $iso = $day->format('Y-m-d');
    $record = pw_record($index, $day);
    check($record !== null, "$iso: missing snapshot day");
    check(pw_iso_key((string) ($record['date'] ?? '')) === $iso, "$iso: wrong snapshot date");
    $checked++;
    $date = pw_board_date($day);
    check($date === $shortDays[(int) $day->format('N')] . ', ' . $day->format('d') . ' '
        . $shortMonths[(int) $day->format('n')], "$iso: board date spelling/format changed");
    check(pw_text_width($captionSize, $font, $date) <= $split - 56,
        "$iso: date overflows at shared heading size");
    $rows = pw_display_rows($day, $record);
    [$labelSize, $timeSize] = pw_timeline_sizes($rows, $record, $font, 88, $timeRight);
    foreach ($rows as $row) {
        $card = pw_highlight_geometry(88, $timeRight, 750);
        $timeLeft = $timeRight - pw_text_width($timeSize, $font, pw_time_12h($record[$row['key']]));
        check($card['left'] === 74 && $card['right'] === $split - 22
            && $card['right'] - $timeRight === 14 && $split - $card['right'] === 22,
            "$iso: {$row['label']} card width/padding depends on text");
        check($timeLeft >= 88 + pw_text_width($labelSize, $font, $row['label']) + 18,
            "$iso: {$row['label']} label and aligned time overlap");
    }
    $next = pw_next_prayer($index, $day);
    if ($next !== null) {
        $heroWidth = $cfg['width'] - ($split + 48) - 48;
        check(pw_text_width(pw_fit(76, $font, $next['label'], $heroWidth, 26), $font, $next['label']) <= $heroWidth,
            "$iso: hero label overflows");
        [$clock, $meridiem] = pw_time_parts($next['time']);
        $reserve = pw_text_width(30, $font, $meridiem) + 22;
        $clockSize = pw_fit(96, $boldFont, $clock, $heroWidth - $reserve, 40);
        check(pw_text_width($clockSize, $boldFont, $clock) + $reserve <= $heroWidth,
            "$iso: hero clock and meridiem collide");
    }
    $footer = pw_ramadan_footer($record, pw_next_ramadan($doc, $day), $day);
    if ($footer !== null) {
        foreach ([[32, 14, $footer[0]], [26, 12, $footer[1]]] as [$maxSize, $minSize, $line]) {
            check(pw_text_width(pw_fit($maxSize, $font, $line, $cfg['width'] - $split - 96, $minSize),
                $font, $line) <= $cfg['width'] - $split - 96, "$iso: Ramadan footer overflows");
        }
        $heroEnd = 200 + pw_text_height($clockSize, $boldFont, $clock);
        $layout = pw_footer_geometry($footer[0], $footer[1], $font,
            $cfg['width'] - $split - 96, $cfg['height'] - 38, $heroEnd);
        check($layout['rule_y'] > $heroEnd + 36 &&
            $layout['sub_y'] + pw_text_height($layout['sub_size'], $font, $footer[1]) <= $cfg['height'] - 38,
            "$iso: footer geometry intersects hero or board edge");
    }
}
check(count($index) === $checked && count($doc['prayerTime']) === $checked,
    'snapshot contains duplicate or out-of-year records');
// The 2026 snapshot cannot supply January 1. Do not invent that day's
// timetable or produce a misleading board until a 2027 snapshot is present.
$jan1 = new DateTimeImmutable('2027-01-01 00:01');
check(pw_record($index, $jan1) === null && pw_next_prayer($index, $jan1) === null
    && !pw_tomorrow_unavailable($index, $jan1), 'Jan 1 must not reuse the old snapshot');
$jan1Out = $outputDir . '/kindle-contract-jan1-missing.png';
try {
    pw_render_board($cfg, $jan1Out, $jan1);
    throw new RuntimeException('Jan 1 unexpectedly rendered without its snapshot');
} catch (RuntimeException $e) {
    check(str_starts_with($e->getMessage(), 'no record for 01-Jan-2027'),
        'Jan 1 should fail for unavailable JAKIM data');
}
print 'PASS Dogica Pixel glyphs (5/S/6, a/A), published/estimated Malay footers, JAKIM parsing, and '
    . $checked . " contiguous days of date/timeline/hero/footer geometry\n";
