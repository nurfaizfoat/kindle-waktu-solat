<?php
declare(strict_types=1);

/**
 * Shared configuration and helpers for the Kindle waktu-solat dashboard.
 *
 * Target runtime: PHP 8.2+ (the cPanel host runs 8.2.29 on LiteSpeed).
 * Syntax newer than 8.2 is deliberately avoided so a local PHP 8.5 test
 * cannot accidentally ship code the host will reject.
 */

/** Central configuration for the board. */
function pw_config(): array
{
    return [
        'zone'        => 'WLY01',
        'zone_label'  => 'WILAYAH PERSEKUTUAN',
        'timezone'    => 'Asia/Kuala_Lumpur',
        'width'       => 1072,
        'height'      => 1448,
        'project_dir' => __DIR__,
        'data_dir'    => __DIR__ . '/data',
        'out_dir'     => __DIR__ . '/out',
        'font_dir'    => __DIR__ . '/assets/fonts',
    ];
}

/* ------------------------------------------------------------------ */
/* Prayer definitions                                                  */
/* ------------------------------------------------------------------ */

/** Prayer rows in display order. 'fard' marks the five obligatory prayers. */
function pw_prayers(): array
{
    return [
        ['key' => 'imsak',   'label' => 'Imsak',   'fard' => false],
        ['key' => 'fajr',    'label' => 'Subuh',   'fard' => true],
        ['key' => 'syuruk',  'label' => 'Syuruk',  'fard' => false],
        ['key' => 'dhuha',   'label' => 'Dhuha',   'fard' => false],
        ['key' => 'dhuhr',   'label' => 'Zohor',   'fard' => true],
        ['key' => 'asr',     'label' => 'Asar',    'fard' => true],
        ['key' => 'maghrib', 'label' => 'Maghrib', 'fard' => true],
        ['key' => 'isha',    'label' => 'Isyak',   'fard' => true],
    ];
}

/** Keys of the five obligatory prayers, in chronological order. */
function pw_fard_keys(): array
{
    return ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
}

/** Display label for a prayer key (e.g. 'maghrib' => 'Maghrib'). */
function pw_label(string $key): string
{
    foreach (pw_prayers() as $p) {
        if ($p['key'] === $key) {
            return $p['label'];
        }
    }
    return strtoupper($key);
}

/** True when the given day is a Friday. */
function pw_is_friday(DateTimeImmutable $day): bool
{
    return $day->format('N') === '5';   // ISO-8601: 1=Mon .. 5=Fri .. 7=Sun
}

/**
 * Prayer rows for one specific day.
 *
 * On Friday the Dhuhr obligation is fulfilled by the Friday congregational
 * prayer, so the row is named Jumaat rather than Zohor. Only the NAME
 * changes - JAKIM publishes a single Dhuhr time for the day and that is the
 * time the Friday prayer is held.
 */
function pw_prayer_rows(DateTimeImmutable $day): array
{
    $rows = pw_prayers();

    if (!pw_is_friday($day)) {
        return $rows;
    }

    foreach ($rows as $i => $prayer) {
        if ($prayer['key'] === 'dhuhr') {
            $rows[$i]['label'] = 'Jumaat';
        }
    }

    return $rows;
}

/** Display label for a prayer key as it applies on a given day. */
function pw_label_on(string $key, DateTimeImmutable $day): string
{
    foreach (pw_prayer_rows($day) as $prayer) {
        if ($prayer['key'] === $key) {
            return $prayer['label'];
        }
    }
    return strtoupper($key);
}

/** True when the day's Hijri month is Ramadan (month 9). */
function pw_is_ramadan(?array $record): bool
{
    $h = pw_hijri_parts((string) ($record['hijri'] ?? ''));
    return $h !== null && $h['month'] === 9;
}

/**
 * The rows actually drawn on the board.
 *
 * Only the five obligatory prayers are listed. Syuruk and Dhuha are omitted:
 * neither is an obligatory prayer, and both sit in the pre-dawn hours where
 * they crowded the timeline's proportional spacing into an unreadable cluster.
 *
 * Imsak is shown ONLY during Ramadan, when the pre-dawn meal cut-off actually
 * matters. Outside Ramadan it is noise.
 */
function pw_display_rows(DateTimeImmutable $day, ?array $record): array
{
    $ramadan = pw_is_ramadan($record);
    $rows    = [];

    foreach (pw_prayer_rows($day) as $prayer) {
        if ($prayer['key'] === 'syuruk' || $prayer['key'] === 'dhuha') {
            continue;
        }
        if ($prayer['key'] === 'imsak' && !$ramadan) {
            continue;
        }
        $rows[] = $prayer;
    }

    return $rows;
}

/* ------------------------------------------------------------------ */
/* HTTP                                                                */
/* ------------------------------------------------------------------ */

/** GET a URL and return the body, or null on failure. Prefers curl. */
function pw_http_get(string $url, int $timeout = 30): ?string
{
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_USERAGENT      => 'kindle-dashboard/1.0',
        ]);
        $body = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if (is_string($body) && $code === 200 && $body !== '') {
            return $body;
        }
    }

    if ((bool) ini_get('allow_url_fopen')) {
        $ctx  = stream_context_create([
            'http' => ['timeout' => $timeout, 'user_agent' => 'kindle-dashboard/1.0'],
        ]);
        $body = @file_get_contents($url, false, $ctx);
        if (is_string($body) && $body !== '') {
            return $body;
        }
    }

    return null;
}

/* ------------------------------------------------------------------ */
/* Snapshot loading                                                    */
/* ------------------------------------------------------------------ */

/** Absolute path of the yearly snapshot for a zone. */
function pw_snapshot_path(string $zone, int $year): string
{
    $cfg = pw_config();
    return sprintf('%s/jakim-%s-%d.json', $cfg['data_dir'], $zone, $year);
}

/** Load and decode the yearly snapshot document. Null when unavailable. */
function pw_load_document(string $zone, int $year): ?array
{
    $path = pw_snapshot_path($zone, $year);
    if (!is_readable($path)) {
        return null;
    }
    $raw = json_decode((string) file_get_contents($path), true);
    if (!is_array($raw) || ($raw['status'] ?? '') !== 'OK!' || empty($raw['prayerTime'])) {
        return null;
    }
    return $raw;
}

/**
 * Map a JAKIM month token to its month number.
 *
 * JAKIM writes dates in MALAY ('31-Dis-2026'), and five of the twelve
 * abbreviations differ from English: Mac/Mar, Mei/May, Ogos/Aug, Okt/Oct,
 * Dis/Dec. Building a lookup key with PHP's format('M') therefore misses
 * those months entirely - which silently broke the board from the 1st of
 * each. Always convert FROM JAKIM's format INTO ISO, never the reverse.
 */
function pw_month_number(string $token): ?int
{
    $map = [
        'jan' => 1, 'feb' => 2, 'mac' => 3, 'apr' => 4, 'mei' => 5, 'jun' => 6,
        'jul' => 7, 'ogos' => 8, 'sep' => 9, 'okt' => 10, 'nov' => 11, 'dis' => 12,
    ];
    return $map[strtolower(trim($token))] ?? null;
}

/** Convert a JAKIM date ('29-Sep-2026') to an ISO key ('2026-09-29'). */
function pw_iso_key(string $jakimDate): ?string
{
    $p = explode('-', $jakimDate);
    if (count($p) !== 3) {
        return null;
    }
    $month = pw_month_number($p[1]);
    if ($month === null) {
        return null;
    }
    return sprintf('%04d-%02d-%02d', (int) $p[2], $month, (int) $p[0]);
}

/** Index a snapshot by ISO date ('2026-09-29' => record). */
function pw_index(?array $doc): array
{
    if ($doc === null || empty($doc['prayerTime'])) {
        return [];
    }
    $index = [];
    foreach ($doc['prayerTime'] as $rec) {
        $key = pw_iso_key((string) ($rec['date'] ?? ''));
        if ($key !== null) {
            $index[$key] = $rec;
        }
    }
    return $index;
}

/** One day's record, or null when the snapshot has no entry for that day. */
function pw_record(array $index, DateTimeImmutable $day): ?array
{
    return $index[$day->format('Y-m-d')] ?? null;
}

/** Combine a date with a 'HH:MM:SS' time string into a DateTimeImmutable. */
function pw_at(DateTimeImmutable $day, string $time): DateTimeImmutable
{
    $parts = array_map('intval', explode(':', $time));
    return $day->setTime($parts[0] ?? 0, $parts[1] ?? 0, 0);
}

/** Minutes since midnight for a 'HH:MM:SS' time string. */
function pw_minutes(string $time): int
{
    $p = array_map('intval', explode(':', $time));
    return ($p[0] ?? 0) * 60 + ($p[1] ?? 0);
}

/** 12-hour label, e.g. '5:54 AM' or '1:06 PM'. */
function pw_time_12h(?string $time): string
{
    if (!is_string($time) || $time === '') {
        return '--:--';
    }
    $p = array_map('intval', explode(':', $time));
    $h = $p[0] ?? 0;
    $m = $p[1] ?? 0;

    $suffix = $h < 12 ? 'AM' : 'PM';
    $h12    = $h % 12;
    if ($h12 === 0) {
        $h12 = 12;
    }

    return sprintf('%d:%02d %s', $h12, $m, $suffix);
}

/** Split a time into its clock part and meridiem: '05:54:00' => ['5:54','AM']. */
function pw_time_parts(?string $time): array
{
    if (!is_string($time) || $time === '') {
        return ['--:--', ''];
    }
    $p = array_map('intval', explode(':', $time));
    $h = $p[0] ?? 0;
    $m = $p[1] ?? 0;

    $suffix = $h < 12 ? 'AM' : 'PM';
    $h12    = $h % 12;
    if ($h12 === 0) {
        $h12 = 12;
    }

    return [sprintf('%d:%02d', $h12, $m), $suffix];
}

/** Split JAKIM's 'YYYY-MM-DD' Hijri value into parts. */
function pw_hijri_parts(string $hijri): ?array
{
    $p = explode('-', $hijri);
    if (count($p) !== 3) {
        return null;
    }
    return ['year' => (int) $p[0], 'month' => (int) $p[1], 'day' => (int) $p[2]];
}

/**
 * Mean Hijri month length in days, measured from JAKIM's own data.
 *
 * Measured rather than assumed: JAKIM's months do NOT alternate 30/29
 * cleanly (observed 30,30,29,29,30,29,29,30,29,30,30), so a textbook
 * assumption would drift out of step within a few months.
 */
function pw_hijri_month_length(?array $doc): float
{
    $starts = [];
    foreach (($doc['prayerTime'] ?? []) as $rec) {
        $h   = pw_hijri_parts((string) ($rec['hijri'] ?? ''));
        $iso = pw_iso_key((string) ($rec['date'] ?? ''));
        if ($h === null || $iso === null || $h['day'] !== 1) {
            continue;
        }
        $starts[] = $iso;
    }

    $sum = 0.0;
    $n   = 0;
    for ($i = 1; $i < count($starts); $i++) {
        $a = strtotime($starts[$i - 1] . ' 12:00:00');
        $b = strtotime($starts[$i] . ' 12:00:00');
        if ($a === false || $b === false) {
            continue;
        }
        $sum += ($b - $a) / 86400;
        $n++;
    }

    // Mean synodic lunar month when a truncated snapshot has <2 month starts.
    // This is only an estimated fallback; published JAKIM dates take priority.
    return $n > 0 ? $sum / $n : 29.53;
}

/**
 * First day of the next Ramadan, with an accuracy flag.
 *
 * JAKIM publishes only the CURRENT Gregorian year, and Ramadan often falls in
 * the next one (Ramadan 1448 begins Feb 2027, outside the 2026 snapshot).
 * When the snapshot does not reach it we extrapolate from JAKIM's own Hijri
 * progression and flag the result as an estimate. From 1 January the next
 * year's data arrives and this reads the published date with no extrapolation.
 *
 * @return array{date:DateTimeImmutable,estimated:bool}|null
 */
function pw_next_ramadan(?array $doc, DateTimeImmutable $now): ?array
{
    if ($doc === null || empty($doc['prayerTime'])) {
        return null;
    }

    $today = $now->setTime(0, 0, 0);

    // 1. A real Ramadan record in the snapshot is authoritative. Require day
    //    1 so this finds the START of Ramadan and not an arbitrary day inside
    //    it - otherwise, once Ramadan was running, the board read "IN 0 DAYS"
    //    because today itself matched.
    foreach ($doc['prayerTime'] as $rec) {
        $h = pw_hijri_parts((string) ($rec['hijri'] ?? ''));
        if ($h === null || $h['month'] !== 9 || $h['day'] !== 1) {
            continue;
        }
        $iso = pw_iso_key((string) ($rec['date'] ?? ''));
        if ($iso === null) {
            continue;
        }
        $d = DateTimeImmutable::createFromFormat('!Y-m-d', $iso);
        if ($d instanceof DateTimeImmutable && $d >= $today) {
            return ['date' => $d, 'estimated' => false, 'hijri_year' => $h['year']];
        }
    }

    // 2. Otherwise extrapolate forward from the last published record.
    $last = end($doc['prayerTime']);
    $h    = pw_hijri_parts((string) ($last['hijri'] ?? ''));
    $iso  = pw_iso_key((string) ($last['date'] ?? ''));
    if ($h === null || $iso === null) {
        return null;
    }

    $from = DateTimeImmutable::createFromFormat('!Y-m-d', $iso);
    if (!$from instanceof DateTimeImmutable) {
        return null;
    }

    $avg = pw_hijri_month_length($doc);

    // Treat next year's Ramadan as month 9 + 12 on an unrolled month axis.
    $target = 9 + ($h['month'] >= 9 ? 12 : 0);

    // Hijri year that Ramadan falls in: the current one, unless this year's
    // Ramadan has already passed.
    $hijriYear = $h['year'] + ($h['month'] >= 9 ? 1 : 0);

    // Days left in the current month, the whole months between, plus the
    // single step onto the 1st of Ramadan.
    $days = ($avg - $h['day']) + (($target - $h['month']) - 1) * $avg + 1;

    return [
        'date'       => $from->modify('+' . (int) round($days) . ' days'),
        'estimated'  => true,
        'hijri_year' => $hijriYear,
    ];
}

/* ------------------------------------------------------------------ */
/* Next-prayer logic                                                   */
/* ------------------------------------------------------------------ */

/**
 * The next obligatory prayer strictly after $now.
 * Rolls over to tomorrow's Subuh once Isyak has passed.
 *
 * @return array{key:string,label:string,time:string,at:DateTimeImmutable,tomorrow:bool}|null
 */
function pw_next_prayer(array $index, DateTimeImmutable $now): ?array
{
    $today    = pw_record($index, $now);
    $tomorrow = pw_record($index, $now->modify('+1 day'));

    foreach (pw_fard_keys() as $key) {
        $time = $today[$key] ?? null;
        if (!is_string($time) || $time === '') {
            continue;
        }
        $at = pw_at($now, $time);
        if ($at > $now) {
            return [
                'key'      => $key,
                'label'    => pw_label_on($key, $now),
                'time'     => substr($time, 0, 5),
                'at'       => $at,
                'tomorrow' => false,
            ];
        }
    }

    $time = $tomorrow['fajr'] ?? null;
    if (is_string($time) && $time !== '') {
        return [
            'key'      => 'fajr',
            'label'    => pw_label_on('fajr', $now->modify('+1 day')),
            'time'     => substr($time, 0, 5),
            'at'       => pw_at($now->modify('+1 day'), $time),
            'tomorrow' => true,
        ];
    }

    return null;
}

/** Today's timetable is valid, but the next day's Subuh is not published. */
function pw_tomorrow_unavailable(array $index, DateTimeImmutable $now): bool
{
    $today = pw_record($index, $now);
    $isha = $today['isha'] ?? null;
    $tomorrow = pw_record($index, $now->modify('+1 day'));
    return is_string($isha) && $isha !== '' && pw_at($now, $isha) <= $now
        && (!is_string($tomorrow['fajr'] ?? null) || $tomorrow['fajr'] === '');
}

/** Human countdown such as 'DALAM 3j 24m'. */
function pw_countdown(DateTimeImmutable $now, DateTimeImmutable $at): string
{
    $secs = $at->getTimestamp() - $now->getTimestamp();
    if ($secs <= 0) {
        return 'SEKARANG';
    }
    $h = intdiv($secs, 3600);
    $m = intdiv($secs % 3600, 60);
    if ($h > 0) {
        return sprintf('DALAM %dj %02dm', $h, $m);
    }
    if ($m > 0) {
        return sprintf('DALAM %dm', $m);
    }
    return sprintf('DALAM %ds', $secs);
}

/* ------------------------------------------------------------------ */
/* Localised names                                                     */
/* ------------------------------------------------------------------ */

/** Malay day name. */
function pw_day_ms(DateTimeImmutable $d): string
{
    $map = [
        'Mon' => 'Isnin', 'Tue' => 'Selasa', 'Wed' => 'Rabu', 'Thu' => 'Khamis',
        'Fri' => 'Jumaat', 'Sat' => 'Sabtu', 'Sun' => 'Ahad',
    ];
    return $map[$d->format('D')] ?? $d->format('l');
}

/** Malay Gregorian month name. */
function pw_month_ms(DateTimeImmutable $d): string
{
    $map = [
        1 => 'Januari', 2 => 'Februari', 3 => 'Mac', 4 => 'April',
        5 => 'Mei', 6 => 'Jun', 7 => 'Julai', 8 => 'Ogos',
        9 => 'September', 10 => 'Oktober', 11 => 'November', 12 => 'Disember',
    ];
    return $map[(int) $d->format('n')] ?? $d->format('F');
}

/** Malay Gregorian month abbreviation for the Ramadan footer. */
function pw_month_short_ms(DateTimeImmutable $d): string
{
    $map = [
        1 => 'Jan', 2 => 'Feb', 3 => 'Mac', 4 => 'Apr', 5 => 'Mei', 6 => 'Jun',
        7 => 'Jul', 8 => 'Ogos', 9 => 'Sep', 10 => 'Okt', 11 => 'Nov', 12 => 'Dis',
    ];
    return $map[(int) $d->format('n')];
}

/** Board date, kept separate from JAKIM's Malay date-token parser. */
function pw_board_date(DateTimeImmutable $now): string
{
    // The board uses SEPT; keep JAKIM's Sep token and footer spelling separate.
    $month = (int) $now->format('n') === 9 ? 'SEPT' : strtoupper(pw_month_short_ms($now));
    return strtoupper(pw_day_ms($now)) . ', ' . $now->format('d') . ' ' . $month;
}

/** Visible Ramadan footer lines, or null when no date can be calculated. */
function pw_ramadan_footer(?array $today, ?array $ramadan, DateTimeImmutable $now): ?array
{
    $hijriToday = pw_hijri_parts((string) ($today['hijri'] ?? ''));
    if (pw_is_ramadan($today) && $hijriToday !== null) {
        return [sprintf('Ramadhan hari ke-%d', $hijriToday['day']), "\xC2\xB7 Puasa hari ini"];
    }
    if ($ramadan === null) {
        return null;
    }

    $days = (int) round(
        ($ramadan['date']->getTimestamp() - $now->setTime(0, 0, 0)->getTimestamp()) / 86400
    );
    // A tilde distinguishes an extrapolation from a published JAKIM date.
    $date = $ramadan['date'];
    $when = sprintf('%s%d %s %s', $ramadan['estimated'] ? '~' : '',
        (int) $date->format('j'), pw_month_short_ms($date), $date->format('Y'));

    return [
        sprintf('Ramadhan %d hari lagi.', $days),
        sprintf("1 Ramadhan %d \xC2\xB7 %s", (int) ($ramadan['hijri_year'] ?? 0), $when),
    ];
}

/** Malay Hijri month name (1-12). */
function pw_hijri_month(int $m): string
{
    $map = [
        1 => 'Muharram', 2 => 'Safar', 3 => 'Rabiulawal', 4 => 'Rabiulakhir',
        5 => 'Jamadilawal', 6 => 'Jamadilakhir', 7 => 'Rejab', 8 => 'Syaaban',
        9 => 'Ramadan', 10 => 'Syawal', 11 => 'Zulkaedah', 12 => 'Zulhijjah',
    ];
    return $map[$m] ?? (string) $m;
}

/** Render JAKIM's 'YYYY-MM-DD' Hijri value as '17 Rabiulakhir 1448'. */
function pw_hijri_text(string $hijri): string
{
    $parts = explode('-', $hijri);
    if (count($parts) !== 3) {
        return $hijri;
    }
    return sprintf('%d %s %s', (int) $parts[2], pw_hijri_month((int) $parts[1]), $parts[0]);
}

/* ------------------------------------------------------------------ */
/* Drawing                                                             */
/* ------------------------------------------------------------------ */

/** Width in pixels of a string at a given size. */
function pw_text_width(float $size, string $font, string $text): float
{
    $bbox = imagettfbbox($size, 0, $font, $text);
    return (float) ($bbox[2] - $bbox[0]);
}

/** Height in pixels of a string at a given size. */
function pw_text_height(float $size, string $font, string $text): float
{
    $bbox = imagettfbbox($size, 0, $font, $text);
    return (float) ($bbox[1] - $bbox[7]);
}

/** Largest half-point size that fits; fail rather than silently clipping. */
function pw_fit(float $maxSize, string $font, string $text, float $maxWidth, float $minSize = 10.0): float
{
    for ($size = $maxSize; $size >= $minSize; $size -= 0.5) {
        if (pw_text_width($size, $font, $text) <= $maxWidth) {
            return $size;
        }
    }
    throw new RuntimeException("text cannot fit within {$maxWidth}px: $text");
}

/** Shared measurements for the timeline (including the card). */
function pw_timeline_sizes(array $rows, array $record, string $font, int $labelX, int $rightEdge): array
{
    for ($labelSize = 26; $labelSize >= 14; $labelSize--) {
        $timeSize = $labelSize - 3;
        $fits = true;
        foreach ($rows as $row) {
            $time = pw_time_12h($record[$row['key']] ?? null);
            // Keep 18px between strings when the time ends at the shared row edge.
            if (pw_text_width($labelSize, $font, $row['label'])
                + pw_text_width($timeSize, $font, $time) + 18 > $rightEdge - $labelX) {
                $fits = false;
                break;
            }
        }
        if ($fits) {
            return [$labelSize, $timeSize];
        }
    }
    throw new RuntimeException('timeline labels and times cannot fit in panel');
}

/**
 * Draw text with a predictable anchor.
 *
 * $y is the visual TOP of the glyph box; $x follows $align.
 */
function pw_text($im, float $size, string $font, float $x, float $y, int $color, string $text, string $align = 'left'): void
{
    $bbox = imagettfbbox($size, 0, $font, $text);
    $w    = $bbox[2] - $bbox[0];

    if ($align === 'center') {
        $x -= $w / 2;
    } elseif ($align === 'right') {
        $x -= $w;
    }

    $baseline = $y - $bbox[7];

    imagettftext(
        $im,
        $size,
        0,
        (int) round($x - $bbox[0]),
        (int) round($baseline),
        $color,
        $font,
        $text
    );
}

/** Draw text vertically centred on $centerY. */
function pw_text_vcenter($im, float $size, string $font, float $x, float $centerY, int $color, string $text, string $align = 'left'): void
{
    pw_text($im, $size, $font, $x, $centerY - pw_text_height($size, $font, $text) / 2, $color, $text, $align);
}

/**
 * Filled rectangle with rounded corners.
 *
 * GD has no rounded-rectangle primitive, so this lays down a cross of two
 * plain rectangles and fills the four corners with matching circles.
 */
function pw_rounded_rect($im, float $x1, float $y1, float $x2, float $y2, float $radius, int $color): void
{
    $r = (int) max(0, min($radius, ($x2 - $x1) / 2, ($y2 - $y1) / 2));

    if ($r === 0) {
        imagefilledrectangle($im, (int) $x1, (int) $y1, (int) $x2, (int) $y2, $color);
        return;
    }

    $d = $r * 2;

    imagefilledrectangle($im, (int) ($x1 + $r), (int) $y1, (int) ($x2 - $r), (int) $y2, $color);
    imagefilledrectangle($im, (int) $x1, (int) ($y1 + $r), (int) $x2, (int) ($y2 - $r), $color);

    imagefilledellipse($im, (int) ($x1 + $r), (int) ($y1 + $r), $d, $d, $color);
    imagefilledellipse($im, (int) ($x2 - $r), (int) ($y1 + $r), $d, $d, $color);
    imagefilledellipse($im, (int) ($x1 + $r), (int) ($y2 - $r), $d, $d, $color);
    imagefilledellipse($im, (int) ($x2 - $r), (int) ($y2 - $r), $d, $d, $color);
}

/** Fixed card bounds around the same label and time anchors as every other row. */
function pw_highlight_geometry(int $labelX, int $timeRightX, int $cy): array
{
    return [
        'left' => $labelX - 14, 'right' => $timeRightX + 14,
        'top' => $cy - 32, 'bottom' => $cy + 32,
    ];
}

/** Position both footer glyph boxes from the last timeline row's visible bottom. */
function pw_footer_geometry(string $main, string $sub, string $font, int $heroWidth, float $rowBottom, float $heroBottom): array
{
    $mainSize = pw_fit(32, $font, $main, $heroWidth, 14);
    $subSize = pw_fit(26, $font, $sub, $heroWidth, 12);
    $subHeight = pw_text_height($subSize, $font, $sub);
    $mainHeight = pw_text_height($mainSize, $font, $main);
    $subTop = $rowBottom - $subHeight;
    $mainTop = $subTop - 28 - $mainHeight;
    $ruleY = $mainTop - 36;
    if ($ruleY < $heroBottom + 36) {
        throw new RuntimeException('Ramadan footer intersects next-prayer hero');
    }
    return [
        'rule_y' => $ruleY, 'main_y' => $mainTop, 'sub_y' => $subTop,
        'main_size' => $mainSize, 'sub_size' => $subSize,
    ];
}

/* ------------------------------------------------------------------ */
/* Daily hadith                                                        */
/* ------------------------------------------------------------------ */

/** Load the local Malay excerpt collection; no network access is needed. */
function pw_hadiths(?string $path = null): array
{
    $path ??= __DIR__ . '/data/hadiths-ms.json';
    $json = @file_get_contents($path);
    if ($json === false) {
        throw new RuntimeException("Cannot read hadith collection: $path");
    }
    try {
        $document = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $e) {
        throw new RuntimeException("Invalid hadith JSON: $path", 0, $e);
    }
    if (!is_array($document) || ($document['schema_version'] ?? null) !== 1
        || ($document['language'] ?? null) !== 'ms'
        || !is_array($document['hadiths'] ?? null)
        || !array_is_list($document['hadiths']) || $document['hadiths'] === []) {
        throw new RuntimeException('Hadith collection must contain a non-empty Malay hadith list');
    }
    $ids = [];
    $texts = [];
    foreach ($document['hadiths'] as $entry) {
        if (!is_array($entry)) {
            throw new RuntimeException('Invalid hadith entry');
        }
        foreach (['id', 'topic', 'text', 'source', 'url'] as $field) {
            if (!is_string($entry[$field] ?? null) || trim($entry[$field]) === '') {
                throw new RuntimeException("Hadith entry requires $field");
            }
        }
        if (preg_match('/^(bukhari|muslim)-([1-9][0-9]*[a-z]?)$/D', $entry['id'], $match) !== 1) {
            throw new RuntimeException('Hadith must reference Sahih al-Bukhari or Sahih Muslim');
        }
        $collection = $match[1] === 'bukhari' ? 'Sahih al-Bukhari' : 'Sahih Muslim';
        if ($entry['source'] !== $collection . ' · ' . $match[2]
            || $entry['url'] !== 'https://sunnah.com/' . $match[1] . ':' . $match[2]) {
            throw new RuntimeException('Hadith source and URL must match its ID');
        }
        if (isset($ids[$entry['id']]) || isset($texts[$entry['text']])) {
            throw new RuntimeException('Duplicate hadith reference or excerpt');
        }
        if (preg_match('/[\r\n\t]/', $entry['text']) === 1) {
            throw new RuntimeException('Hadith excerpt must be a single paragraph');
        }
        $ids[$entry['id']] = true;
        $texts[$entry['text']] = true;
    }
    return $document['hadiths'];
}

/** One entry per KL calendar day; all entries appear before the cycle repeats. */
function pw_daily_hadith(DateTimeImmutable $now): array
{
    $day = $now->setTimezone(new DateTimeZone('Asia/Kuala_Lumpur'))->setTime(0, 0);
    $epoch = new DateTimeImmutable('2026-09-30', new DateTimeZone('Asia/Kuala_Lumpur'));
    $days = (int) $epoch->diff($day)->format('%r%a');
    $entries = pw_hadiths();
    $count = count($entries);
    return $entries[(($days % $count) + $count) % $count];
}

/** Wrap using actual font metrics instead of a character-count estimate. */
function pw_hadith_lines(string $text, string $font, float $size, int $width): array
{
    $lines = [];
    $line = '';
    foreach (explode(' ', $text) as $word) {
        if (pw_text_width($size, $font, $word) > $width) {
            throw new RuntimeException('Hadith word exceeds panel width');
        }
        $candidate = $line === '' ? $word : $line . ' ' . $word;
        if ($line !== '' && pw_text_width($size, $font, $candidate) > $width) {
            $lines[] = $line;
            $line = $word;
        } else {
            $line = $candidate;
        }
    }
    if ($line !== '') {
        $lines[] = $line;
    }
    return $lines;
}

/** Add only to the empty space between the existing hero and footer. */
function pw_draw_hadith($im, array $hadith, string $font, int $x, int $width,
    float $heroBottom, float $footerTop, int $black, int $gray): void
{
    $headingSize = pw_fit(26, $font, 'HADIS HARI INI', $width, 14);
    $sourceSize = pw_fit(20, $font, $hadith['source'], $width, 14);
    $note = 'Petikan maksud hadis';
    $noteSize = pw_fit(18, $font, $note, $width, 14);
    $headingHeight = pw_text_height($headingSize, $font, 'HADIS HARI INI');
    $sourceHeight = pw_text_height($sourceSize, $font, $hadith['source']);
    $noteHeight = pw_text_height($noteSize, $font, $note);
    $available = $footerTop - $heroBottom - 96;
    for ($size = 22; $size >= 18; $size--) {
        $lines = pw_hadith_lines($hadith['text'], $font, $size, $width);
        $lineHeight = (int) ceil(pw_text_height($size, $font, 'Ag') + 18);
        $height = $headingHeight + 64 + count($lines) * $lineHeight
            + 24 + $sourceHeight + 18 + $noteHeight;
        if ($height <= $available) {
            break;
        }
    }
    if ($height > $available) {
        throw new RuntimeException('Hadith does not fit between hero and footer');
    }
    $top = $heroBottom + 48 + ($available - $height) / 2;
    pw_text($im, $headingSize, $font, $x, $top, $black, 'HADIS HARI INI');
    $ruleY = (int) round($top + $headingHeight + 26);
    imageline($im, $x, $ruleY, $x + $width, $ruleY, $black);
    $y = $top + $headingHeight + 64;
    foreach ($lines as $line) {
        pw_text($im, $size, $font, $x, $y, $black, $line);
        $y += $lineHeight;
    }
    $y += 24;
    pw_text($im, $sourceSize, $font, $x, $y, $black, $hadith['source']);
    pw_text($im, $noteSize, $font, $x, $y + $sourceHeight + 18, $gray, $note);
}

/* ------------------------------------------------------------------ */
/* Snapshot fetching                                                   */
/* ------------------------------------------------------------------ */

/**
 * Fetch a yearly JAKIM snapshot and write it to disk atomically.
 *
 * @return int number of records written
 * @throws RuntimeException on network, payload, or write failure
 */
function pw_fetch_snapshot(array $cfg, int $year): int
{
    $zone   = $cfg['zone'];
    $target = pw_snapshot_path($zone, $year);
    $url    = sprintf(
        'https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=year&zone=%s',
        $zone
    );

    $body = pw_http_get($url, 60);
    if ($body === null) {
        throw new RuntimeException("request failed: $url");
    }

    $data = json_decode($body, true);
    if (!is_array($data) || ($data['status'] ?? '') !== 'OK!' || empty($data['prayerTime'])) {
        throw new RuntimeException(sprintf(
            'unexpected payload (status=%s)',
            (string) ($data['status'] ?? '?')
        ));
    }

    $count = count($data['prayerTime']);
    if ($count < 300) {
        // Refuse to overwrite a good snapshot with a truncated one.
        throw new RuntimeException("refusing to write a short snapshot ($count records)");
    }

    if (!is_dir($cfg['data_dir']) && !mkdir($cfg['data_dir'], 0755, true)) {
        throw new RuntimeException("cannot create {$cfg['data_dir']}");
    }

    if (is_file($target)) {
        @copy($target, $target . '.bak');
    }

    $tmp = $target . '.tmp';
    if (file_put_contents($tmp, $body) === false) {
        throw new RuntimeException("cannot write $tmp");
    }
    if (!rename($tmp, $target)) {
        throw new RuntimeException("cannot move $tmp into place");
    }
    @chmod($target, 0644);

    return $count;
}

/* ------------------------------------------------------------------ */
/* Board rendering                                                     */
/* ------------------------------------------------------------------ */

/**
 * Render the waktu-solat board to a greyscale PNG.
 *
 * The write is atomic (temp file + rename) so a web request can never
 * serve a half-written image.
 *
 * @return array{next:?array,doc:?array,now:DateTimeImmutable}
 * @throws RuntimeException when data or assets are unusable
 */
function pw_render_board(array $cfg, string $out, DateTimeImmutable $now): array
{
    $doc   = pw_load_document($cfg['zone'], (int) $now->format('Y'));
    $index = pw_index($doc);
    $today = pw_record($index, $now);

    if ($today === null) {
        throw new RuntimeException(sprintf(
            'no record for %s (zone %s)',
            $now->format('d-M-Y'),
            $cfg['zone']
        ));
    }

    $next    = pw_next_prayer($index, $now);
    $ramadan = pw_next_ramadan($doc, $now);

    // Original Dogica Pixel TTF, bundled with its own OFL notice.
    $font = $cfg['font_dir'] . '/dogicapixel.ttf';
    $clockFont = $cfg['font_dir'] . '/dogicapixelbold.ttf';
    foreach ([$font, $clockFont] as $requiredFont) {
        if (!is_readable($requiredFont)) {
            throw new RuntimeException("missing font: $requiredFont");
        }
    }

    $outDir = dirname($out);
    if (!is_dir($outDir) && !mkdir($outDir, 0755, true)) {
        throw new RuntimeException("cannot create $outDir");
    }

    $W = (int) $cfg['width'];
    $H = (int) $cfg['height'];

    $im = imagecreatetruecolor($W, $H);
    $BLACK = imagecolorallocate($im, 0, 0, 0);
    $WHITE = imagecolorallocate($im, 255, 255, 255);
    $GRAY  = imagecolorallocate($im, 85, 85, 85);   // #555 on white after 16-level quantization
    $DIM   = imagecolorallocate($im, 185, 185, 185);   // secondary on black

    imagefilledrectangle($im, 0, 0, $W, $H, $WHITE);

    /* Two-tone panels -------------------------------------------------- */

    // No header bar: the black panel runs the full height on the left and
    // carries the date, with the timetable beneath it. The white panel
    // on the right holds the next-prayer hero and a Ramadan footer.
    $splitX = (int) round($W * 0.45);

    imagefilledrectangle($im, 0, 0, $splitX, $H, $BLACK);

    /* Left panel: the date --------------------------------------------- */

    $padL = 28;

    $dateLine = pw_board_date($now);
    $leftWidth = $splitX - 2 * $padL;
    $heroX      = $splitX + 48;
    $heroWidth  = $W - $heroX - 48;
    $caption = 'SOLAT SETERUSNYA';
    $headingSize = pw_fit(26, $font, $caption, $heroWidth, 14);
    if (pw_text_width($headingSize, $font, $dateLine) > $leftWidth) {
        throw new RuntimeException('date does not fit at the shared heading size');
    }
    $contentTop = 48;
    pw_text($im, $headingSize, $font, $padL, $contentTop, $WHITE, $dateLine);
    $dateBottom = $contentTop + pw_text_height($headingSize, $font, $dateLine);

    /* Layout ----------------------------------------------------------- */

    /* Hero (right panel): the next prayer ----------------------------- */

    $heroBottom = $contentTop;
    pw_text($im, $headingSize, $font, $heroX, $contentTop, $GRAY, $caption);
    if ($next !== null) {

        // Leave breathing room below the caption without pushing the hero down.
        $nameY    = $contentTop + 112;
        $nameSize = pw_fit(76, $font, $next['label'], $heroWidth, 26);
        pw_text($im, $nameSize, $font, $heroX, $nameY, $BLACK, $next['label']);

        // The meridiem is set smaller beside the clock rather than inside it,
        // so the digits can stay large without the 'AM' eating the width.
        [$clock, $meridiem] = pw_time_parts($next['time']);

        $timeY    = $nameY + pw_text_height($nameSize, $font, $next['label']) + 40;
        $merSize  = 30;
        // Reserve exactly the width the meridiem needs before sizing the
        // clock, so the two can never collide.
        $reserve  = $meridiem === '' ? 0 : pw_text_width($merSize, $font, $meridiem) + 22;
        $timeSize = pw_fit(96, $clockFont, $clock, $heroWidth - $reserve, 40);
        pw_text($im, $timeSize, $clockFont, $heroX, $timeY, $BLACK, $clock);
        $clockH = pw_text_height($timeSize, $clockFont, $clock);
        $heroBottom = $timeY + $clockH;

        if ($meridiem !== '') {
            $clockW = pw_text_width($timeSize, $clockFont, $clock);
            $merH   = pw_text_height($merSize, $font, $meridiem);
            pw_text(
                $im,
                $merSize,
                $font,
                $heroX + $clockW + 22,
                $timeY + $clockH - $merH,
                $BLACK,
                $meridiem
            );
        }
    } elseif (pw_tomorrow_unavailable($index, $now)) {
        // Do not substitute today's Subuh for an unpublished tomorrow. The
        // left panel still has a valid timetable, so explain only the gap.
        $heading = 'Jadual esok';
        $detail = 'belum tersedia';
        $headingY = $contentTop + 112;
        $headingSize = pw_fit(62, $font, $heading, $heroWidth, 26);
        $detailY = $headingY + pw_text_height($headingSize, $font, $heading) + 26;
        $detailSize = pw_fit(38, $font, $detail, $heroWidth, 18);
        pw_text($im, $headingSize, $font, $heroX, $headingY, $BLACK, $heading);
        pw_text($im, $detailSize, $font, $heroX, $detailY, $GRAY, $detail);
        $heroBottom = $detailY + pw_text_height($detailSize, $font, $detail);
    } else {
        $message = 'TIADA DATA SOLAT';
        $messageSize = pw_fit(38, $font, $message, $heroWidth, 14);
        pw_text($im, $messageSize, $font, $heroX, $contentTop + 80, $GRAY, $message);
        $heroBottom = $contentTop + 80 + pw_text_height($messageSize, $font, $message);
    }

    /* Timeline (left column) ------------------------------------------ */

    // Vertical position is proportional to the clock gap between prayers, so
    // the shape of the day is visible at a glance instead of implied by
    // evenly spaced rows. Rows are day-aware: Dhuhr is named Jumaat on Friday,
    // and Imsak appears only during Ramadan.
    $rows       = pw_display_rows($now, $today);
    // The highlight card is drawn 32px ABOVE and below the entry's centre, so
    // the top entry needs that much clearance under the date line.
    $tlTop      = $dateBottom + 32 + 54;
    $tlBottom   = $H - 38 - 32;
    $spineX     = 40;
    $labelX     = 88;   // a clear gap from the spine, as the timeline's edge
    $timeRightX = $splitX - 36;  // card finishes 22px before the panel edge

    $mins     = [];
    $firstMin = null;
    $lastMin  = null;
    foreach ($rows as $prayer) {
        $t = $today[$prayer['key']] ?? null;
        $m = is_string($t) && $t !== '' ? pw_minutes($t) : null;
        $mins[$prayer['key']] = $m;
        if ($m !== null) {
            if ($firstMin === null || $m < $firstMin) {
                $firstMin = $m;
            }
            if ($lastMin === null || $m > $lastMin) {
                $lastMin = $m;
            }
        }
    }

    $span   = max(1, (int) $lastMin - (int) $firstMin);
    $usable = $tlBottom - $tlTop;
    $minGap = 54;   // keeps labels legible when prayers fall minutes apart

    [$rowFont, $timeFont] = pw_timeline_sizes($rows, $today, $font, $labelX, $timeRightX);

    $ys   = [];
    $prev = null;
    foreach ($rows as $prayer) {
        $m = $mins[$prayer['key']];
        if ($m === null) {
            continue;
        }
        $y = $tlTop + (($m - $firstMin) / $span) * $usable;
        if ($prev !== null && $y < $prev + $minGap) {
            $y = $prev + $minGap;
        }
        $ys[$prayer['key']] = $y;
        $prev = $y;
    }

    // If the minimum gaps pushed the last entry past the column, compress
    // the whole set proportionally so it still fits on screen.
    if (!empty($ys)) {
        $maxY = max($ys);
        if ($maxY > $tlBottom) {
            $k = ($tlBottom - $tlTop) / max(1.0, $maxY - $tlTop);
            foreach ($ys as $key => $value) {
                $ys[$key] = $tlTop + ($value - $tlTop) * $k;
            }
        }

        $ordered = array_keys($ys);
        imagesetthickness($im, 5);
        imageline(
            $im,
            $spineX,
            (int) $ys[$ordered[0]],
            $spineX,
            (int) $ys[$ordered[count($ordered) - 1]],
            $GRAY
        );
        imagesetthickness($im, 1);
    }

    $nowMinutes = pw_minutes($now->format('H:i:s'));

    $lastRowBottom = null;
    foreach ($rows as $prayer) {
        if (!isset($ys[$prayer['key']])) {
            continue;
        }
        $cy = (int) $ys[$prayer['key']];

        $t      = $today[$prayer['key']] ?? null;
        $isNext = $next !== null && !$next['tomorrow'] && $next['key'] === $prayer['key'];
        $passed = is_string($t) && $t !== '' && pw_minutes($t) <= $nowMinutes;

        $timeText = pw_time_12h(is_string($t) ? $t : null);
        $rowTimeX = $timeRightX;
        if ($isNext) {
            // Inverted against the black panel: a white card with black text.
            // Span the row's fixed time edge, with equal 14px outer insets.
            $card = pw_highlight_geometry($labelX, $timeRightX, $cy);
            pw_rounded_rect(
                $im,
                $card['left'],
                $card['top'],
                $card['right'],
                $card['bottom'],
                0.15 * ($card['bottom'] - $card['top']),
                $WHITE
            );
            $fg   = $BLACK;
        } else {
            $fg   = $prayer['fard'] ? $WHITE : $DIM;
        }

        // Solid white for passed/next; future rings have black centres and
        // strong white outlines so they remain visible on the black panel.
        if ($passed || $isNext) {
            imagefilledellipse($im, $spineX, $cy, 20, 20, $WHITE);
        } else {
            imagefilledellipse($im, $spineX, $cy, 24, 24, $WHITE);
            imagefilledellipse($im, $spineX, $cy, 12, 12, $BLACK);
            imagesetthickness($im, 4);
            imageellipse($im, $spineX, $cy, 24, 24, $WHITE);
            imagesetthickness($im, 1);
        }

        pw_text_vcenter($im, $rowFont, $font, $labelX, $cy, $fg, $prayer['label']);
        pw_text_vcenter(
            $im,
            $timeFont,
            $font,
            $rowTimeX,
            $cy,
            $fg,
            $timeText,
            'right'
        );
        // Match the last row's visible glyphs (or its white highlight when
        // Isyak is next), not a fixed distance from the board edge.
        $labelHeight = pw_text_height($rowFont, $font, $prayer['label']);
        $timeHeight = pw_text_height($timeFont, $font, $timeText);
        $lastRowBottom = max(
            $cy + max($labelHeight, $timeHeight) / 2,
            $isNext ? $card['bottom'] : 0
        );
    }

    /* Ramadan footer: align its subtitle to the last visible row. ----- */
    $footer = pw_ramadan_footer($today, $ramadan, $now);
    $footerTop = $H - 48;
    if ($footer !== null && $lastRowBottom !== null) {
        [$ramMain, $ramSub] = $footer;
        $foot = pw_footer_geometry($ramMain, $ramSub, $font, $heroWidth, $lastRowBottom, $heroBottom);
        $footerTop = $foot['rule_y'];
        imagesetthickness($im, 2);
        imageline($im, $heroX, (int) round($foot['rule_y']), $W - 48, (int) round($foot['rule_y']), $BLACK);
        imagesetthickness($im, 1);
        pw_text($im, $foot['main_size'], $font, $heroX, $foot['main_y'], $BLACK, $ramMain);
        pw_text($im, $foot['sub_size'], $font, $heroX, $foot['sub_y'], $GRAY, $ramSub);
    }

    pw_draw_hadith($im, pw_daily_hadith($now), $font, $heroX, $heroWidth,
        $heroBottom, $footerTop, $BLACK, $GRAY);

    /* Output ----------------------------------------------------------- */

    // E-ink is 16-level greyscale: flatten to grey, then to a small palette.
    // Dithering is left OFF so text edges stay crisp instead of noisy.
    imagefilter($im, IMG_FILTER_GRAYSCALE);
    imagetruecolortopalette($im, false, 16);

    // imagetruecolortopalette() chooses its palette with a median-cut quantiser
    // whose exact output DIFFERS BETWEEN GD BUILDS - PHP 8.2 produced a ramp
    // topping out at 252 while PHP 8.5 produced one reaching 255. That would
    // make the board's contrast depend on which PHP the host happens to run.
    // Snapping every entry onto a fixed 16-step ramp makes the result
    // deterministic and guarantees true black and true white for maximum
    // e-ink contrast.
    $entryCount = imagecolorstotal($im);
    for ($i = 0; $i < $entryCount; $i++) {
        $entry = imagecolorsforindex($im, $i);
        $level = (int) (round(((int) $entry['red']) / 17) * 17);
        $level = max(0, min(255, $level));
        imagecolorset($im, $i, $level, $level, $level);
    }

    $tmp = $out . '.tmp';
    $ok  = imagepng($im, $tmp, 9);
    imagedestroy($im);

    if (!$ok) {
        @unlink($tmp);
        throw new RuntimeException("failed to write $tmp");
    }
    if (!rename($tmp, $out)) {
        @unlink($tmp);
        throw new RuntimeException("cannot move $tmp into place");
    }
    @chmod($out, 0644);

    return ['next' => $next, 'doc' => $doc, 'now' => $now];
}
