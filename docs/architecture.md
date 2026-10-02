# Architecture

This document describes the technical design of the Kindle prayer-times display
in detail: the full data flow from `dashboard/board.php` to the e-ink panel, why
the native status chrome no longer appears, why installing the board as the
native screensaver is sufficient, the on-device normalisation/gate design, the
safety invariants the scripts enforce, and the library-scriptlet launcher that
stands in for KUAL on this firmware.

Everything below is traceable to the files in this repository unless explicitly
marked **unverified**. Device paths come from the scripts that read or write
them.

---

## 1. Full data flow: `board.php` to the panel

### 1.1 Server side (`dashboard/`)

- **Entry point.** `dashboard/board.php` is a web entry point (no cron, no PHP
  CLI required). It is the URL the device fetches; the device reads that URL
  from `/mnt/us/dashboard/board-url.conf`, with the placeholder
  `https://example.com/waktu/board.php` used only as a not-configured sentinel
  (see the main README's "Set up your own server"). It sets
  `Cache-Control: no-store, no-cache, must-revalidate, max-age=0`.
- **Cache window.** A rendered board is reused for 60 seconds
  (`$cacheTtl = 60`) so refreshing every few minutes does not re-render on every
  request.
- **Snapshot freshness.** `lib.php` stores the yearly JAKIM snapshot at
  `data/jakim-WLY01-<year>.json`. `board.php` refreshes it at most once a day
  (`> 86400` seconds) via `pw_fetch_snapshot()`, which fetches
  `https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=year&zone=WLY01`,
  refuses a snapshot with fewer than 300 records, backs up any existing file to
  `.bak`, and writes atomically (temp + rename).
- **Render.** `lib.php::pw_render_board()` draws the board:
  - Canvas 1072x1448 (`pw_config()` `width`/`height`), timezone
    `Asia/Kuala_Lumpur`, zone `WLY01`, label `WILAYAH PERSEKUTUAN`.
  - Layout: a black left panel (45% of width) with the date and the proportional
    prayer timeline; a white right panel with the next-prayer hero, the daily
    hadith and the Ramadan footer.
  - Rows are day-aware: the five obligatory prayers (Subuh/Zohor/Asar/Maghrib/
    Isyak) are always drawn; on Friday `Zohor` is labelled `Jumaat`; `Imsak` is
    drawn only during Ramadan; `Syuruk` and `Dhuha` are never drawn.
  - Output pre-processing: `IMG_FILTER_GRAYSCALE` then
    `imagetruecolortopalette($im, false, 16)` (16 colours, no dithering), then
    every palette entry is snapped onto a fixed 16-step ramp
    (`round(red/17)*17`) so contrast does not depend on the host PHP's GD build.
  - Written with `imagepng($im, $tmp, 9)` and moved into place with `rename()`
    (atomic), `chmod 0644`.
- **Result:** a low-bit indexed PNG (the scripts describe it as 4-bit) at
  1072x1448 whose palette has been forced onto 16 grey levels.
- **Failure behaviour.** `board.php` catches render exceptions, logs them, and
  serves the last good `board.png` if one exists; otherwise it returns HTTP 500
  with `Board unavailable and no cached render exists.` `lib.php` also refuses
  to invent the first day of a new year: with only a 2026 snapshot, 2027-01-01
  raises `no record for 01-Jan-2027` rather than reusing stale data.
- **Hadith.** `data/hadiths-ms.json` holds 50 narrations (Sahih al-Bukhari and
  Sahih Muslim). `pw_daily_hadith()` selects one per calendar day in
  `Asia/Kuala_Lumpur` as `(days since 2026-09-30) mod 50`, so the selection is
  stable within a day and independent of caller timezone. Details in
  `dashboard/HADITHS.md`.
- **Deployment.** `deploy/kindle-dashboard-hadith.zip` is the prepared bundle
  (server `waktu/` tree plus `hadiths-ms.json`). `deploy/stage/waktu/` is the
  staging tree; `deploy/stage/waktu/.htaccess` forces `no-store`/`no-cache` and
  `Options -Indexes`. The `dashboard/lib.php` and
  `deploy/stage/waktu/lib.php` copies are byte-identical, as are the hadith JSON
  copies (verified with `cmp`).

### 1.2 Device side (`kindle-device/screensaver-board/bin/`)

`refresh.sh` is the device pipeline:

1. **Mount guard.** Refuses to run (exit 10) unless `/mnt/us` appears as a real
   mount in `/proc/mounts`. This prevents writing a shadow `/mnt/us/dashboard`
   on the rootfs while the userstore is unmounted (USB drive mode).
2. **Single-instance lock.** `mkdir /mnt/us/dashboard/refresh.lock` holding
   `pid`. If the lock exists and its PID is alive, it refuses (exit 9); a stale
   lock is removed and re-acquired. Traps clean the lock on exit/signals.
3. **Fetch.** `curl -s -m 30 --max-filesize 2097152 -o <tmp> <url>`, falling
   back to `wget -q -T 30 -O <tmp> <url>`. Both branches are subject to the same
   post-hoc size check against `MAXBYTES=2097152` (2 MiB), because `wget` has no
   portable max-size flag. Empty downloads fail.
4. **Magic-byte check.** First four bytes must be `89504e47` (`\x89PNG`).
5. **Normalise on-device** (section 3 below).
6. **Gate** (section 3 below).
7. **Preserve last-known-good.** Before replacing `/mnt/us/dashboard/board.png`,
   copy it to `board.png.bak`. A failure to back up aborts (exit 2).
8. **Install.** Move the accepted file over `board.png`, then delegate to
   `set-screensaver.sh`.
9. **`set-screensaver.sh`** validates the PNG (magic, exact 1072x1448 from the
   IHDR), refuses if `/mnt/us/linkss` is absent (exit 2), installs to
   `/mnt/us/linkss/screensavers/bg_ss00.png` atomically, and verifies the
   installed file.

`set-screensaver.sh` always installs the FW >= 5.5 final filename
`/mnt/us/linkss/screensavers/bg_ss00.png`, not the legacy
`bg_<group>_ssNN.png`. On FW >= 5.5 linkss's `shuffless` names pool files
`bg_ss00.png`, `bg_ss01.png`, ... (its `ss_prefix` is `bg_ss` for
`K5_ATLEAST_55`); the legacy panel-group name is only the boot-time form that
`shuffless` renames. After a verified install it calls the sourced helper
`bin/lib-pool.sh::pool_quarantine_extras` to MOVE every other `*.png` in the pool
into `/mnt/us/dashboard/screensaver-quarantine/` (recoverable, never deleted), so
the pool holds exactly one file and no extras make linkss cycle. It refuses to
install a source that is not exactly 1072x1448 (fail closed) and, after install,
verifies both the IHDR dimensions and that the installed basename is exactly
`bg_ss00.png` (exit 7 otherwise).

---

## 2. Why native chrome no longer appears

On the retired framebuffer-takeover design (`kindle-device/dashboard.sh`),
the script set `lipc-set-prop com.lab126.powerd preventScreenSaver 1` and ran
`/etc/init.d/framework stop` **without checking the exit status**, then painted
the PNG with `fbink`. If the framework did not actually stop, the native status
bar kept repainting the clock and battery over the board.

The screensaver route removes the contention instead of fighting it:

- The board is installed as an ordinary **native screensaver image** under
  `/mnt/us/linkss/screensavers/`. The linkss ScreenSavers hack supplies custom
  images to the framework's own sleep path; nothing takes over the framebuffer
  and nothing is painted by a competing process.
- linkss **bind-mounts** `/mnt/us/linkss/screensavers` onto
  `/usr/share/blanket/screensaver`, so the framework reads the pool file live
  from the userstore. Replacing the correctly-named `bg_ssNN.png` is therefore
  visible at the next sleep with no restart.
- The framework's sleep screen is drawn by **libblanket**, which renders the
  screensaver full-screen with **no status chrome** (no clock/battery bar). That
  is why the board appears clean. (The libblanket implementation itself is
  firmware code and is **unverified** here; the only in-repository evidence for
  it is `bin/diagnose.sh`, which inspects `/usr/share/blanket` and
  `/usr/share/blanket/screensaver`.)
- The status bar is only drawn by the framework while the device is **awake and
  running the reading UI**. It is not part of the sleep image.

Because the change is confined to the custom-image pool, the stock sleep path
is otherwise untouched: the device still enters its normal sleep state and still
returns to the reading UI on wake.

---

## 3. On-device normalisation and the `eips` gate

### 3.1 Candidate order: grayscale-8, then PNG8 palette

The server emits a low-colour indexed PNG. The device renderer rejects it
outright; the exact error text quoted in `refresh.sh` is:

```
eips: paint_image> cannot open "...":8bit only
```

Rather than depend on the server being changed, `refresh.sh` normalises the
file on-device using the ImageMagick that linkss ships:

```
/mnt/us/linkss/bin/convert   (or /mnt/us/linkss/bin/mogrify)
```

Because the `vfat` userstore grants no execute bit, the binary is copied to
`/tmp/linkss_convert` (tmpfs, always executable) before use.

For each acceptable 8-bit form, in this order:

1. `convert <tmp> -colorspace Gray -depth 8 <out>`  (grayscale candidate)
2. `convert <tmp> -colors 256 -depth 8 PNG8:<out>`  (8-bit palette candidate)

the candidate is drawn with the device renderer. The **first candidate the
renderer accepts wins** and is installed. This is deliberate: `eips` itself is
the arbiter, so the bundle does not have to guess which 8-bit form this
firmware/panel tolerates. Rejected candidates are removed and logged
(`note: the <mode> candidate was rejected by the renderer`).

If linkss's ImageMagick is missing, the script logs
`note: linkss ImageMagick not found - gating the file exactly as fetched` and
gates the raw download. If nothing passes, it refuses to install (exit 3),
leaves the previous good board in place, and points at `to-png8.py` /
`README.md` for the host-side re-encode.

### 3.2 The gate itself

`bin/test-format.sh`:

- Requires `/mnt/us` to be a real mount (logs to
  `/mnt/us/dashboard/screensaver.log`, exit 10 otherwise).
- Rejects a missing/empty file, a non-PNG (magic `89504e47`), and an IHDR size
  that is not 1072x1448.
- Draws the file with `/usr/sbin/eips -f -g <png>` and inspects the exit code.
  On success it logs `PASS: device renderer accepted the PNG (eips exit 0)`; on
  failure it logs the exit code and the `to-png8.sh` line (see caveats in the
  main README).

`eips` shares the framebuffer path the screensaver engine uses, so a success in
this gate is strong evidence the file is safe before anything is installed.

### 3.3 Why the final filename matters

On FW >= 5.5 the linkss `shuffless` names pool files `bg_ss00.png`,
`bg_ss01.png`, ... (its `ss_prefix` is `bg_ss` for `K5_ATLEAST_55`). The legacy
`bg_<group>_ss<NN>.png` token (for example `bg_large_ss00.png`) is only the
boot-time form: `shuffless` renames it to `bg_ssNN.png` when it runs at boot. So
writing the legacy name takes effect only after a reboot, while writing the final
name `bg_ss00.png` is read live at the next sleep. `set-screensaver.sh`:

- always installs exactly `/mnt/us/linkss/screensavers/bg_ss00.png`;
- after a verified install, calls `pool_quarantine_extras` from the sourced
  `bin/lib-pool.sh` to MOVE every other `*.png` in the pool into
  `/mnt/us/dashboard/screensaver-quarantine/` (a name collision gets a `.$$`
  suffix), so the pool holds exactly one file;
- never deletes a pool file: quarantine is recoverable by moving a file back by
  hand, and a failed move is logged as a WARNING that the pool may still cycle.

### 3.4 Live updates: the refresh daemon and the upstart autostart

Refreshing used to require tapping a library scriptlet. `bin/refresh-daemon.sh`
keeps the board current without a tap:

- It is installed as an upstart job, `/etc/init/screensaver-board-refresh.conf`,
  by `bin/install-refresh-autostart.sh` (inside a guarded `mntroot rw`/`ro`
  block). The job is `start on started framework` / `stop on stopping framework`
  when `/etc/init/framework.conf` exists, else `lab126_gui` when
  `/etc/init/lab126_gui.conf` exists, else `start on runlevel [2345]` with no
  stop line (with a logged WARNING). It declares `respawn`,
  `respawn limit 10 300`, `kill timeout 30` (so the daemon's trap can run on
  stop) and runs
  `exec /bin/sh /mnt/us/extensions/screensaver-board/bin/refresh-daemon.sh`.
- The daemon refreshes once after a 10s settle, then loops in **sliced** waits of
  at most 10s each (`lipc-wait-event -s 10 com.lab126.powerd
  wakeupFromSuspend`), classifying each return as a wake event or a timeout by
  how quickly it returned (clock-jump safe). It refreshes on a wake event with a
  60s debounce and otherwise at least every 3600s while awake. Repeated
  sub-2s returns are treated as a broken `lipc-wait-event` and it falls back to
  the sleep-based hourly timer. The short slices keep the loop responsive to
  INT/TERM/HUP and let it re-check the `/mnt/us` mount each cycle.
- If `/mnt/us` is not mounted the daemon waits 60s and retries rather than
  exiting, so an upstart respawn cannot burn its budget while the userstore is
  unmounted.
- Each cycle calls `refresh.sh` up to 3 times, 20s apart, wrapped in
  `timeout 300` when available; exit 8 (board URL not configured) is permanent
  and is not retried. The loop never aborts: a failed refresh keeps the previous
  board (`refresh.sh` preserves it).
- `refresh-daemon.log` and `screensaver.log` are rotated to `<file>.1` once they
  exceed 256 KiB.
- While the device is **asleep** no process runs, so the visible board is as
  fresh as the last refresh before sleep. The daemon refreshes as soon as the
  device wakes.
- It is single-instance (a `refresh-daemon.lock` directory holding a PID, backed
  by `refresh-daemon.pid`, with a live-PID plus cmdline check) and it never stops
  or touches the framework. `bin/remove-refresh-autostart.sh` is the rollback: it
  stops the upstart job first, then the daemon, then removes the job file inside
  the same guarded rootfs block.

Because linkss bind-mounts the pool onto `/usr/share/blanket/screensaver`, the
replacement of an already-correctly-named `bg_ss00.png` is read at the next sleep
without a framework restart. The restart/reboot requirement applies to the
**first install**, when `shuffless` must run to name the pool files.

---

## 4. Safety invariants

These are enforced across `refresh.sh`, `set-screensaver.sh`, `lib-pool.sh`,
`prepare-ldsymlink.sh`, `remove-ldsymlink.sh`, `refresh-daemon.sh`,
`install-refresh-autostart.sh` and `remove-refresh-autostart.sh`.

1. **Never delete files it does not own.** `set-screensaver.sh` installs
   `bg_ss00.png` and then moves every other `*.png` in the pool to
   `/mnt/us/dashboard/screensaver-quarantine/` via `lib-pool.sh`; nothing is
   deleted and quarantined files can be restored by hand. A failed move is only a
   logged WARNING. The bundle README states the same rule.
2. **Back up before overwrite.**
   - `refresh.sh` copies `board.png` to `board.png.bak` immediately before
     replacing it, and aborts if the backup fails.
   - `set-screensaver.sh` copies the existing destination to `<dest>.bak` once
     (the backup is kept, not refreshed, so it always holds the file that was
     there first).
3. **Single-instance.** `refresh.sh` (`.lock`/`pid`) and `set-screensaver.sh`
   (`set-screensaver.lock`/`pid`) use an atomic `mkdir` lock with a live-PID
   check, so two library taps cannot race. `refresh-daemon.sh` uses a pidfile
   whose PID must be alive **and** whose `/proc/<pid>/cmdline` still names
   `refresh-daemon.sh`, so a stale pidfile is replaced.
4. **Preserve the last-known-good board.** A failed fetch or a failed gate
   leaves `board.png` untouched and exits non-zero. Temporary files use the
   `$$` PID suffix and are cleaned up.
5. **Always return the rootfs to read-only.** `prepare-ldsymlink.sh`,
   `remove-ldsymlink.sh`, `install-refresh-autostart.sh` and
   `remove-refresh-autostart.sh` are the only scripts that write to the rootfs,
   and only inside a guarded `mntroot rw` / `mntroot ro` block. The writable flag
   is set **before** `mntroot rw`, so the `EXIT` trap always attempts a restore;
   after `mntroot ro` the state is verified against `/proc/mounts` and the script
   exits non-zero (7) with a "reboot" message if it is still `rw`. Signal traps
   (`INT TERM HUP`) run the same restore.
6. **Fail closed on the symlink.** `prepare-ldsymlink.sh` refuses to create a
   dangling link if `/lib/ld-linux-armhf.so.3` is missing; it treats an existing
   `/lib/ld-linux.so.3` as "done" only when it resolves to
   `/lib/ld-linux-armhf.so.3` and refuses to touch a wrong or dangling one.
   `remove-ldsymlink.sh` removes only a symlink that points at
   `/lib/ld-linux-armhf.so.3`, so it cannot delete a stock or foreign file.
7. **No mount fabrication.** Every script refuses to create `/mnt/us/dashboard`
   when `/mnt/us` is not a real mount; `set-screensaver.sh` additionally refuses
   to create `/mnt/us/linkss`, because a fake directory the stock framework
   would never read only masks the real problem.
8. **No framework interference.** The screensaver scripts write only under
   `/mnt/us/dashboard` and the linkss screensaver path. They never stop the
   framework and never touch the running legacy dashboard. The refresh daemon
   only calls `refresh.sh`; it never stops or restarts the framework.
9. **Failed refresh keeps the previous board.** `refresh.sh` leaves the previous
   `board.png`/pool file in place on a fetch, normalise or gate failure, and the
   daemon retries without ever aborting its loop.

---

## 5. The library-scriptlet launcher (no KUAL)

This firmware has no KUAL and no working Kindlet launcher, and no SSH. The only
launcher available is **library scriptlets**: a `.sh` file placed in
`/mnt/us/documents/` whose header declares:

```sh
# Name: SS Board 2 Install Board
# Author: nurfaizfoat
# Icon: /mnt/us/dashboard/ssb-2-install.png
```

The Kindle shows that file in the library as a tappable "book". Tapping it runs
the script. The bundle ships seven scriptlets
(`documents/ssb-1-diagnose.sh` to `documents/ssb-7-autostart-off.sh`); each one:

- checks that its target `bin/` script exists and prints a clear message
  (`Bundle not found on this Kindle.` + the expected path) if the bundle has not
  been copied to `/mnt/us/extensions/screensaver-board/`;
- runs the target with `sh <script>`, captures `$?`;
- prints an on-screen summary carrying the exit code, a plain-English verdict
  and the log path, and exits with the same code.

They deliberately **omit** the `# DontUseFBInk` header line. With that line the
Kindle suppresses the text output; without it, the summary is painted on the
device screen, so the result can be read without a PC.

`ssb-5-install-linkss.sh` is the one scriptlet that does not call a `bin/`
script: it invokes MRPI directly with the same action MRPI's own `menu.json`
declares:

```sh
cd /mnt/us/extensions/MRInstaller
sh ./bin/mrinstaller.sh launch_installer
```

It refuses (clear on-screen message) if `MRInstaller/bin/mrinstaller.sh` is
missing, if `/mnt/us/mrpackages` is missing, or if the package folder is empty.
MRPI normally reboots the device when it finishes, so the on-screen summary may
be cut short.

`ssb-6-autostart-on.sh` and `ssb-7-autostart-off.sh` call
`bin/install-refresh-autostart.sh` and `bin/remove-refresh-autostart.sh`, which
install/remove the `screensaver-board-refresh` upstart job described in section
3.4. Each has its own numbered icon (`ssb-6-autostart-on.png`,
`ssb-7-autostart-off.png`), so the library shows distinct thumbnails for all
seven entries.

### The secondary KUAL route

The bundle also carries `config.xml` + `menu.json` (KUAL 2.x). It is **not
usable on this device as-is** and is kept only so the same bundle works if a
launcher (KUAL or a Mesquito helper) is installed later. Its menu mirrors the
scriptlets and adds two actions that have no library entry on this device:
**Test PNG format (eips)** (`bin/test-format.sh`) and **Set board as
screensaver** (`bin/set-screensaver.sh`); it also carries **Enable auto-refresh
(boot)** and **Disable auto-refresh (rollback)** for the upstart job.

---

## 6. Legacy design, kept as fallback

`kindle-device/dashboard.sh` is the retired framebuffer-takeover loop. Its
notable engineering, in case it is ever revived:

- **Preflight before takeover.** It fetches and validates the board *before*
  stopping the framework; on network failure it logs and leaves the UI
  untouched.
- **Teardown armed early.** `cleanup` is installed (`trap cleanup EXIT`) before
  the framework is stopped, and the stop flag (`FRAMEWORK_STOPPED`) is set before
  the stop command so a deferred signal cannot strand the device with no UI.
- **Screensaver restore.** It remembers `preventScreenSaver` and restores it on
  teardown (otherwise the device would stay awake until reboot).
- **Single-instance hunting.** Besides a pidfile it scans `/proc/*/cmdline` for
  `/dashboard.sh` and terminates stale instances.
- **Power-button watcher.** A bounded `lipc-wait-event -s 600` watcher on
  `readyToSuspend,goingToScreenSaver,wakeupFromSuspend` reintroduces the stop
  flag so a correctly behaved instance steps aside on sleep.
- `kindle-device/stop-dashboard.sh` is the recovery button: it raises the stop
  flag, SIGTERM/SIGKILLs any `/dashboard.sh` process, clears the control files,
  restores `preventScreenSaver 0`, and restarts the framework.

Its fatal flaw was the unscoped, unverified `framework stop`: when the stop did
not take effect, the native status bar redrew over the board. That is the reason
the screensaver route superseded it.

---

## 7. Unverified items (explicit)

- The internals of **libblanket**, the framework's sleep-screen renderer, and
  the claim that it draws with no status chrome. Only the `/usr/share/blanket`
  paths inspected by `diagnose.sh` are visible from this repository.
- The internals of the **linkss** hack (how it selects and cycles
  screensaver files, and its exact handling of files in a non-matching panel
  group).
- The **live-read assumption**: that replacing an already-correctly-named
  `bg_ss00.png` in the bind-mounted pool is picked up at the next sleep without
  a restart. This is inferred from linkss bind-mounting
  `/mnt/us/linkss/screensavers` onto `/usr/share/blanket/screensaver` plus its
  FW >= 5.5 `bg_ss` prefix logic, not from reading the linkss source here.
- The **upstart job-name detection heuristic**: `/etc/init/framework.conf` ->
  `framework`, else `/etc/init/lab126_gui.conf` -> `lab126_gui`. A different
  firmware may name its main job something else; the runlevel fallback avoids a
  hard dependency but has not been exercised on this device.
- The exact **cost in seconds** of the on-device ImageMagick conversion.
- The **MRInstaller log filename**: `ssb-5` says only "Check its log under
  `$MRPI/log/`". The conventional filename `mrinstaller.log` is used in the
  troubleshooting doc but is not asserted by the repository scripts.
- The exact **packaging/version strings** of the MobileRead linkss and MRPI
  downloads; these are external artifacts not stored here.
