# Daily hadith collection

`data/hadiths-ms.json` contains 50 distinct narrations from Sahih al-Bukhari
and Sahih Muslim. Each entry includes a stable ID, topic, short Malay excerpt,
display reference and link to the complete narration on Sunnah.com. The
references and selected passages were checked on 30 September 2026.

The Malay text is a concise translation of the selected meaning, not an
official published Malay translation or the complete narration. The screen
labels it **Petikan maksud hadis**. Context and the full Arabic/English text
remain available through each entry's `url`.

## Rotation

- One entry per calendar day in `Asia/Kuala_Lumpur`.
- The first entry corresponds to 30 September 2026.
- Entries follow JSON array order, with topics mixed for variety.
- All 50 appear once before repeating on day 51 (19 November 2026).
- Refreshing or restarting does not change that day's selection.
- The new selection appears on the first dashboard refresh after midnight;
  the existing web PNG cache can delay rendering by up to 60 seconds.
- No hadith API, internet request, database or saved progress is required.

## Editing

Edit `hadiths` in the JSON file. Use unique IDs such as `bukhari-6018` or
`muslim-2699a`; `source` and `url` must match that ID. Keep each excerpt short
and on one paragraph, and check its meaning against the linked narration.
The `topic` field is for organising the collection; it is not drawn on screen.

Adding entries automatically lengthens the cycle. Changing the count or array
order changes which entry is selected on a date, because the index is the
number of calendar days since the starting date modulo the collection size.

Run from the project root:

```sh
php dashboard/test_hadiths.php
php dashboard/test_board.php
```

The hadith test checks a complete cycle, local midnight, malformed files and
the rendering of every excerpt. Unreadable or invalid JSON stops rendering;
the existing web error handling serves the last good PNG.

## Upload

Deploy **both** the updated `lib.php` and `data/hadiths-ms.json` into the
server's `waktu` directory. The prepared `deploy/kindle-dashboard-hadith.zip`
includes both files together with the existing dashboard assets. The Kindle
script does not need changing.
