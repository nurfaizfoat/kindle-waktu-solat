![Waktu Solat on a Kindle Paperwhite 3](Waktu%20Solat%20Kindle%20Promo.png)

# Kindle Prayer-Times Display

A jailbroken Kindle Paperwhite 3 is used as a wall / prayer-times display. A
remote PHP server renders a 1072x1448 PNG prayer board (Malaysian prayer times
for zone WLY01, a daily hadith, and a Ramadan countdown), and the Kindle shows
it as its **native screensaver**. Closing the magnetic cover shows the board;
opening it returns to reading. Because it is the native sleep image, none of the
stock clock/battery chrome is drawn over the board.

- Target device: Kindle Paperwhite 3 (7th generation), firmware **5.16.2.1.1**,
  jailbroken.
- Board source: `https://example.com/waktu/board.php` (placeholder - this is
  **your own** deployment; see [Set up your own server](#set-up-your-own-server))
- Screensaver engine: NiLuJe's **ScreenSavers (linkss)** hack.
- Launcher: **library scriptlets** (this firmware has no KUAL and no working
  Kindlet launcher, and no SSH).

> Repository: <https://github.com/nurfaizfoat/kindle-waktu-solat>

---

## How it works

![How the generated dashboard image reaches the Kindle sleep screen](Kindle%20Dashboard%20PNG%20Flow.png)

1. **Server renders the PNG.** `dashboard/board.php` is a web entry point that
   renders the board on demand (no cron, no CLI) and serves it with
   `Cache-Control: no-store`. `dashboard/lib.php` draws 1072x1448, flattens to
   grayscale, converts to a 16-colour palette, snaps every palette entry onto a
   fixed 16-step ramp, and writes the PNG atomically. A failed render falls back
   to the last good PNG.
2. **Device fetches.** `bin/refresh.sh` downloads the board over plain HTTP
   (`curl -m 30 --max-filesize 2097152`, or `wget -T 30`), checks the PNG magic
   bytes (`89504e47`) and enforces a 2 MiB size cap. A failed fetch keeps the
   previous board.
3. **On-device 8-bit normalise.** The server emits a low-bit indexed PNG, which
   the device renderer rejects. `refresh.sh` converts it on-device using the
   ImageMagick that linkss ships (`/mnt/us/linkss/bin/convert` or `mogrify`),
   copied to `/tmp/linkss_convert` because the `vfat` userstore carries no
   execute bit.
4. **`eips` gate.** `bin/test-format.sh` draws each candidate with the stock
   renderer `/usr/sbin/eips -f -g <png>`. Only a file the renderer accepts is
   installed.
5. **Install as the native screensaver.** `bin/set-screensaver.sh` copies the
   accepted PNG to `/mnt/us/linkss/screensavers/bg_ss00.png` (the FW >= 5.5
   final name for this 1072x1448 panel; linkss's `shuffless` names pool files
   `bg_ssNN.png`). Any other `*.png` in the pool is then moved to
   `/mnt/us/dashboard/screensaver-quarantine/` (recoverable) so exactly one
   screensaver remains. The linkss hack bind-mounts that directory onto the
   framework's sleep path, so the board appears with no framebuffer takeover and
   no status chrome, and a later replacement of `bg_ss00.png` is read at the
   next sleep without a restart.

The older framebuffer-takeover dashboard is described in
[Why the old dashboard was retired](#why-the-old-dashboard-was-retired); its
files are kept as a fallback.

---

## Hardware and software prerequisites

- Kindle Paperwhite 3, 7th generation.
- Firmware **5.16.2.1.1**.
- The device must be **jailbroken**.
- **Special Offers (ads) must be disabled first.** If ads are still active, the
  ad framework owns the sleep screen and overrides the ScreenSavers hack.
- **No KUAL and no SSH on this device.** All on-device actions are tapped from
  the library through library scriptlets.
- USB access to the Kindle userstore (`/mnt/us`) from a computer, to copy files.
- The linkss package and MRPI package are downloaded from MobileRead (see
  Part 1); those downloads require a forum session and are not stored in this
  repository.

---

## Repository layout

Only the project paths are listed. Personal and third-party material
(purchased e-book backups, KOReader binaries, jailbreak staging, local tooling
artifacts) is not part of the project and is intended to be excluded via
`.gitignore` (no `.gitignore` exists in the repository at the time of writing).

| Path | Role |
| --- | --- |
| `dashboard/` | The remote PHP board server (renders the PNG). |
| `dashboard/board.php` | Web entry point: renders on demand and serves `out/board.png`. |
| `dashboard/lib.php` | All rendering and data logic (`pw_render_board`, JAKIM parsing, hadith selection, layout). |
| `dashboard/fetch.php` | CLI entry point: refresh the yearly JAKIM snapshot. |
| `dashboard/render.php` | CLI entry point: render once (optional `HH:MM` time override). |
| `dashboard/php_check.php` | Temporary host-capability probe (delete from the server after use). |
| `dashboard/test_board.php` | Local contract test for layout, dates, hadith and geometry. |
| `dashboard/test_hadiths.php` | Local test for the hadith collection, rotation and rendering. |
| `dashboard/HADITHS.md` | Notes on the daily hadith collection and its rotation. |
| `dashboard/assets/fonts/` | Dogica Pixel fonts (`dogicapixel.ttf`, `dogicapixelbold.ttf`) and their licence; the directory also holds other, currently unreferenced font files. |
| `dashboard/data/` | `hadiths-ms.json`, the JAKIM snapshot `jakim-WLY01-2026.json` (and its `.bak`). |
| `dashboard/out/` | Rendered output: `board.png`, `board-png8.png`, `board-hadith-preview.png`. |
| `deploy/` | Release bundles and staging for the server. |
| `deploy/kindle-dashboard.zip` | Server bundle without the hadith collection. |
| `deploy/kindle-dashboard-hadith.zip` | Server bundle including `hadiths-ms.json` and the updated `lib.php`. |
| `deploy/stage/waktu/` | Staging tree matching the server's `waktu` directory. |
| `kindle-device/` | On-device scripts and the screensaver bundle. |
| `kindle-device/screensaver-board/` | **The active screensaver bundle** (see below). |
| `kindle-device/dashboard.sh` | Old framebuffer-takeover dashboard (retired; fallback). |
| `kindle-device/stop-dashboard.sh` | Old stop/recovery button for the dashboard. |
| `kindle-device/waktu-solat.sh` | Old library launcher for the dashboard. |
| `kindle-device/RUNME.sh` | Old `;log runme` trigger (fallback path). |
| `kindle-device/test_display.sh` | Old one-shot display test. |
| `kindle-device/probe_power.sh` | Old read-only power-event probe. |
| `kindle-device/icon.png`, `kindle-device/stop-icon.png` | Old library thumbnails. |

Inside `kindle-device/screensaver-board/`:

| Path | Role |
| --- | --- |
| `README.md` | The bundle's own README (authoritative reference for the bundle's scripts). |
| `config.xml`, `menu.json` | KUAL 2.x metadata/menu (secondary route; not usable on this device). |
| `bin/diagnose.sh` | Read-only diagnostic; writes `screensaver-diag.log`. |
| `bin/refresh.sh` | Fetch, normalise, gate and install the board. |
| `bin/set-screensaver.sh` | Install exactly one screensaver (`bg_ss00.png`) under `/mnt/us/linkss`; quarantine extras. |
| `bin/lib-pool.sh` | Sourced helper: move non-`bg_ss00.png` pool files to the quarantine dir. |
| `bin/test-format.sh` | `eips` gate. |
| `bin/refresh-daemon.sh` | Background refresher: refresh on wake and at least hourly while awake. |
| `bin/install-refresh-autostart.sh` | Install/start the `screensaver-board-refresh` upstart job (guarded rootfs write). |
| `bin/remove-refresh-autostart.sh` | Rollback of that upstart job (guarded rootfs write). |
| `bin/prepare-ldsymlink.sh` | Firmware 5.17+ `/lib/ld-linux.so.3` workaround. |
| `bin/remove-ldsymlink.sh` | Rollback of that workaround. |
| `bin/to-png8.py` | Host-side (PC-only) Pillow converter; never runs on the Kindle. |
| `documents/ssb-1-diagnose.sh` | Library scriptlet: run the diagnostic. |
| `documents/ssb-2-install.sh` | Library scriptlet: install/refresh the board. |
| `documents/ssb-3-fix-ld.sh` | Library scriptlet: apply the firmware fix. |
| `documents/ssb-4-undo-ld.sh` | Library scriptlet: undo the firmware fix. |
| `documents/ssb-5-install-linkss.sh` | Library scriptlet: run MRPI to install linkss. |
| `documents/ssb-6-autostart-on.sh` | Library scriptlet: enable auto-refresh. |
| `documents/ssb-7-autostart-off.sh` | Library scriptlet: disable auto-refresh. |
| `tests/` | Host-only test harness; never deployed to the Kindle. |
| `icons/ssb-1-diagnose.png` to `icons/ssb-7-autostart-off.png` | Library thumbnails, one per scriptlet entry (1-7). |

---

## Set up your own server

This repository does not ship a server that you can use out of the box. You host
the board image yourself and point the Kindle at your URL through a small
on-device configuration file. Do this before the device setup in Part 1.

### 1. Understand what the server must do

The server must serve a **PNG** at a URL the Kindle can fetch. The image is
**1072x1448** (the PW3 panel size). It is generated on demand: the PHP entry
point renders the board when the URL is requested and reuses the last render for
a short window (`$cacheTtl = 60` seconds in `dashboard/board.php`), so frequent
refreshes do not re-render every time. The board is recomputed server-side from
the prayer-time data; the Kindle only downloads the finished PNG.

### 2. Deploy the server files

Copy the `dashboard/` tree to a PHP host:

- `dashboard/board.php` - web entry point: renders on demand and serves the PNG.
- `dashboard/lib.php` - all rendering and data logic (zone, layout, JAKIM
  parsing, daily hadith).
- `dashboard/render.php` - CLI entry point to render once (optional; needs shell
  access).
- `dashboard/fetch.php` - CLI entry point to refresh the yearly JAKIM snapshot
  (optional; `board.php` refreshes it itself at most once a day).
- `dashboard/data/` - `hadiths-ms.json` and the JAKIM snapshot
  (`jakim-WLY01-2026.json`).
- `dashboard/assets/fonts/` - the Dogica Pixel fonts the renderer uses.

`deploy/stage/waktu/` is a ready-to-upload staging copy of the same tree (it
uses a `waktu/` directory name instead of `dashboard/`, and adds a `.htaccess`
that forces `no-store`/`no-cache` and disables directory listing). The
`deploy/*.zip` files are packaged versions of that staging tree. Either copy
`dashboard/` directly, or upload the staging tree / unzip one of the bundles.

### 3. Meet the host requirements

- **PHP with the GD extension** (PNG and FreeType support), because the renderer
  draws TrueType text and writes a PNG with GD. `dashboard/php_check.php` is a
  temporary capability probe that reports these; delete it from the server after
  use.
- **Outbound HTTPS access**, because the prayer-time data is fetched from the
  JAKIM e-solat API (`https://www.e-solat.gov.my/...`). The yearly snapshot is
  cached in `dashboard/data/`, so the API is contacted at most once a day.
- The host must be able to write `dashboard/data/` and `dashboard/out/`.
- The target runtime is **PHP 8.2+** (`dashboard/lib.php`), chosen because the
  owner's host runs PHP 8.2.29 on LiteSpeed; syntax newer than 8.2 is
  deliberately avoided.

The **zone is configurable**. The default is `WLY01`, and it is set by the
`'zone'` key of the array returned by `pw_config()` in `dashboard/lib.php`
(`'zone_label'` and `'timezone'` sit alongside it). The sample data in
`dashboard/data/` is for `WLY01`; change that key to the JAKIM zone code you
need. The snapshot filename follows the zone
(`jakim-<zone>-<year>.json`), so a different zone looks for a different file.

### 4. Verify the deployment before touching the Kindle

From a computer with network access to your host:

```sh
curl -s -o /tmp/board.png https://your-host/path/board.php
file /tmp/board.png
```

`file` should report `PNG image data`. Confirm the size is exactly 1072x1448:

```sh
python3 -c 'import struct; d=open("/tmp/board.png","rb").read(33); print(*struct.unpack(">II", d[16:24]))'
# -> 1072 1448
```

Continue only when the response is a PNG of exactly that size.

### 5. Point the Kindle at your URL

Create the configuration file on the device:

1. Copy `kindle-device/board-url.conf.sample` to the Kindle as
   `/mnt/us/dashboard/board-url.conf`.
2. Edit it so `BOARD_URL` is your deployment, keeping the quotes:
   `BOARD_URL="https://your-host/path/board.php"`.

The device scripts (`refresh.sh`, `dashboard.sh`, `test_display.sh`) source that
file as a POSIX sh fragment. If it is missing, unreadable, or still holds the
placeholder `https://example.com/waktu/board.php`, the scripts log a clear error
and exit non-zero **without attempting any download**.

### 6. Use HTTPS

Strongly prefer HTTPS. The device validates the download **only** by PNG magic
bytes and a 2 MiB size cap. There is no signature and no content
authentication, so a board served over plain HTTP can be substituted in transit
by anyone on the network path. HTTPS does not change the device-side validation,
but it stops network attackers from swapping the image.

> Note: the server emits a low-bit indexed PNG, which the device renderer
> rejects with an `8bit only` error. This is handled automatically on the device
> by the normalisation step in `refresh.sh`; you do not need to fix it on the
> server. See [`docs/architecture.md`](docs/architecture.md), section 3.1.

---

## Part 1 - One-time device setup

Each step is a file action over USB or an on-device tap. The steps are ordered
so that each prerequisite exists before it is used; this is why the bundle
deploy comes before the MRPI tap.

### 1. Deploy the bundle and its library entries

Copy from `kindle-device/screensaver-board/` to the Kindle over USB:

1. `extensions/screensaver-board/` -> `/mnt/us/extensions/screensaver-board/`
2. `documents/*.sh` -> `/mnt/us/documents/`
3. `icons/*.png` -> `/mnt/us/dashboard/`

The scriptlets point their `# Icon:` lines at `/mnt/us/dashboard/ssb-*.png`, one
numbered thumbnail per entry (`ssb-1-diagnose.png` ... `ssb-7-autostart-off.png`),
so all seven library entries show distinct thumbnails. You may need to let the
Kindle rescan the library (or reboot) before new entries appear; a library entry
whose `# Icon:` file is missing or shared with another entry can fail to show.

> The bundle must be deployed before **SS Board 5 Install LinksS** can be
> tapped, because that scriptlet runs `bin/mrinstaller.sh` from the MRPI
> extension that this same deploy step copies into place.

### 2. Install MRPI (one-time)

MRPI is the MR Package Installer. This firmware has no KUAL, so MRPI is invoked
directly by `ssb-5-install-linkss.sh`, which runs
`./bin/mrinstaller.sh launch_installer` from the MRInstaller extension
directory.

1. Obtain the MRPI package from its MobileRead thread (download; no repository
   copy is kept here).
2. Copy its `extensions/MRInstaller/` into `/mnt/us/extensions/`, so that
   `/mnt/us/extensions/MRInstaller/bin/mrinstaller.sh` exists.
3. No search-bar command is needed on this route.

### 3. Download the linkss package and extract the installer

1. Download the current **ScreenSavers (linkss)** package from the MobileRead
   "Kindle ScreenSavers" / Snapshots thread. This requires a logged-in
   MobileRead session, so it cannot be fetched automatically.
   The archive is typically named `kindle-linkss-0.25.N-r18981.tar.xz`, where
   `N` is the current build.
2. Extract
   `ScreenSavers/Update_linkss_0.25.N_install_pw2_and_up.bin` from that archive.

(The exact version/build strings above are the ones published on the thread; they
may change with a newer snapshot.)

### 4. Queue the linkss installer

Copy the extracted `.bin` into `/mnt/us/mrpackages/` on the Kindle.

### 5. Tap **SS Board 5 Install LinksS**

On the device, tap **SS Board 5 Install LinksS**. It runs MRPI, which installs
the package(s) waiting in `/mnt/us/mrpackages`. **MRPI normally reboots the
Kindle when it finishes, so the on-screen summary may be cut short by that
reboot - that is expected.**

### 6. Delete the linkss sample screensaver

Reconnect USB and delete
`/mnt/us/linkss/screensavers/00_you_can_delete_me-kv.png` (the sample file linkss
ships). Leaving it in place makes linkss cycle between the sample and the board,
so the board would show only some of the time.

### 7. Tap **SS Board 2 Install Board**

Tap **SS Board 2 Install Board**. It fetches the current board, normalises it to
8-bit, gates it through `eips`, and only then installs it under
`/mnt/us/linkss/screensavers/`. A failed fetch or a failed gate leaves the
previous good board untouched.

> After changing the screensaver file, the framework must be restarted, or the
> device fully rebooted, before linkss picks up the new pool. Reboot with the
> device **UNPLUGGED** (NiLuJe's guidance; booting while plugged in can break
> screensavers).

### 8. Verify

1. Reboot with the device **unplugged**.
2. Close the lid (or press power to sleep). The board should appear.
3. Open the lid. The normal reading UI should return.
4. Repeat once. It should be deterministic - there is exactly one screensaver
   file.

If it does not behave, see [Troubleshooting](#troubleshooting).

> If the MRPI install of linkss succeeds but screensavers never change, apply
> the **SS Board 3 Firmware Fix** (the `/lib/ld-linux.so.3` symlink workaround),
> reboot unplugged, and retry. `diagnose.sh` writes a
> `ld-linux symlink (5.17+ workaround check)` section you can read afterwards.

### 9. Enable auto-refresh

Tap **SS Board 6 Auto-Refresh On**. It installs and starts the
`screensaver-board-refresh` upstart job, which runs `bin/refresh-daemon.sh` in
the background: it refreshes the board on **every wake from sleep** and **at
least hourly while the device stays awake**. The first refresh happens ~10s after
the job starts. It opens the rootfs read-write only inside a guarded
`mntroot rw`/`ro` block.

Because the device cannot run anything while it is **asleep**, the board you see
is as fresh as the last refresh before sleep; the daemon refreshes again as soon
as the device wakes. The daemon log is
`/mnt/us/dashboard/refresh-daemon.log`.

To turn it off again, tap **SS Board 7 Auto-Refresh Off**.

---

## Part 2 - Everyday use / refreshing the board

With auto-refresh enabled (**SS Board 6**), the board updates itself on every
wake and at least hourly while awake - no tap needed. To update it immediately,
tap **SS Board 2 Install Board**: it fetches the latest PNG, normalises and
gates it, backs up the current `board.png` to `board.png.bak`, and installs the
new one. Once the pool file is correctly named `bg_ss00.png`, the replacement is
read at the next sleep **without a reboot**; only the very first install needs a
reboot (so `shuffless` can name the pool files).

On success, `/mnt/us/dashboard/screensaver.log` ends with lines like:

```
=== refresh start ===
normalised to 8-bit (gray) and accepted by the renderer
backup created: /mnt/us/dashboard/board.png.bak (last-known-good board preserved)
fetched OK: /mnt/us/dashboard/board.png (NNNNN bytes)
installed: /mnt/us/linkss/screensavers/bg_ss00.png (NNNNN bytes, IHDR 1072x1448)
set-screensaver exit=0
=== refresh done ===
```

The on-screen summary from the scriptlet ends with `Result: board installed as
the screensaver. Reboot unplugged, then test sleep.`

---

## The seven library entries

| Library entry | Runs | Writes | When to use |
| --- | --- | --- | --- |
| **SS Board 1 Diagnose** | `bin/diagnose.sh` (read-only) | `/mnt/us/dashboard/screensaver-diag.log` | Any time you need to inspect the device state: firmware, linkss presence, `blanket` files, the `ld-linux` symlink. Changes nothing. |
| **SS Board 2 Install Board** | `bin/refresh.sh` (fetch -> normalise -> gate -> install) | `/mnt/us/dashboard/screensaver.log` | Normal refresh and first install of the board. |
| **SS Board 3 Firmware Fix** | `bin/prepare-ldsymlink.sh` (5.17+ workaround) | `/mnt/us/dashboard/screensaver.log` | Only if linkss installs but no screensaver ever appears. Creates `/lib/ld-linux.so.3 -> /lib/ld-linux-armhf.so.3` in a guarded `mntroot rw`/`ro` block. |
| **SS Board 4 Undo Firmware Fix** | `bin/remove-ldsymlink.sh` (rollback) | `/mnt/us/dashboard/screensaver.log` | Undo entry 3. Removes only that one symlink. |
| **SS Board 5 Install LinksS** | runs MRPI `./bin/mrinstaller.sh launch_installer` | `/mnt/us/extensions/MRInstaller/log/` | Install the linkss package queued in `/mnt/us/mrpackages`. Reboots when it finishes. |
| **SS Board 6 Auto-Refresh On** | `bin/install-refresh-autostart.sh` | `/mnt/us/dashboard/screensaver.log` | Install the `screensaver-board-refresh` upstart job so the board refreshes on every wake and at least hourly while awake. |
| **SS Board 7 Auto-Refresh Off** | `bin/remove-refresh-autostart.sh` | `/mnt/us/dashboard/screensaver.log` | Undo entry 6: stop the daemon and remove the upstart job. Safe when nothing was installed. |

All scriptlets deliberately carry **no** `# DontUseFBInk` line, so their final
on-screen summary is visible on the device.

---

## Why the old dashboard was retired

The original approach (`kindle-device/dashboard.sh`, launched by
`waktu-solat.sh` / `RUNME.sh`) **took over the panel** instead of using the
native sleep path. `dashboard.sh`:

- set `preventScreenSaver 1` via lipc (`lipc-set-prop com.lab126.powerd
  preventScreenSaver 1`), suppressing the native screensaver, and
- stopped the framework with `$FRAMEWORK stop >/dev/null 2>&1`, discarding the
  command's exit status, then painted with `fbink`.

Because the stop was not verified, the framework (and its native status bar)
could keep redrawing the clock and battery over the board. The native
screensaver route avoids the problem entirely: nothing takes over the panel, and
libblanket paints the sleep image with no status chrome.

The old files (`dashboard.sh`, `stop-dashboard.sh`, `waktu-solat.sh`,
`RUNME.sh`, `test_display.sh`, `probe_power.sh`, `icon.png`, `stop-icon.png`)
are **preserved as a fallback**. Nothing in the screensaver bundle modifies or
deletes them.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| The stock / default screensaver appears instead of the board. | `linkss/screensavers/` is empty, so linkss disables itself. | Run **SS Board 2 Install Board**, then reboot unplugged. |
| `eips: paint_image> cannot open "...":8bit only` in the log. | The fetched PNG was below 8-bit and the renderer rejected it. | `refresh.sh` normalises on-device automatically with linkss's ImageMagick. If `/mnt/us/linkss/bin/convert` is missing, install linkss first (**SS Board 5**). |
| The board appears only SOME of the time. | More than one PNG in `linkss/screensavers/` - linkss cycles through them. | Run **SS Board 2 Install Board**; it moves every extra `*.png` to `/mnt/us/dashboard/screensaver-quarantine/` (recoverable), leaving exactly one. |
| MRPI install is greyed out or fails. | The firmware 5.17+ loader symlink is missing. | Run **SS Board 3 Firmware Fix**, reboot unplugged, retry. |
| Nothing happens when tapping a library entry. | The library needs a rescan. | Eject and reconnect USB, or restart the device. |
| Everything looks installed but screensavers never change. | The framework was not restarted after the first install (shuffless must name the pool files). | Reboot the first time, always with the device **UNPLUGGED**; later refreshes of the correctly-named `bg_ss00.png` are read at the next sleep. |
| The board shows a stale time / old prayer times. | The board is a static image and auto-refresh is off (or the device was asleep). | Enable auto-refresh (**SS Board 6**); it refreshes on wake and at least hourly while awake. Check `/mnt/us/dashboard/refresh-daemon.log`. |

The expanded form of this table, with exact log strings and where each log
lives, is in [`docs/troubleshooting.md`](docs/troubleshooting.md).

> Always reboot or restart with the device **UNPLUGGED**. This is NiLuJe's
> guidance for the ScreenSavers hack; booting while plugged in can break
> screensavers.

---

## Rollback

- **Remove just the custom board:** delete the installed
  `/mnt/us/linkss/screensavers/bg_ss00.png` and reboot. If a
  `bg_ss00.png.bak` exists, restore it first
  (`mv bg_ss00.png.bak bg_ss00.png`). The device falls back to the stock
  screensaver set. Files moved aside during install are recoverable from
  `/mnt/us/dashboard/screensaver-quarantine/` (move one back by hand if needed).
- **Restore an earlier board PNG:** the installer keeps
  `/mnt/us/dashboard/board.png.bak` (the file that was there before the first
  overwrite). Copy it over `board.png` and run **SS Board 2** again, or install
  it directly.
- **Stop auto-refresh:** tap **SS Board 7 Auto-Refresh Off**. It stops the
  daemon and removes the `screensaver-board-refresh` upstart job, leaving the
  current board in place.
- **Remove the firmware fix (only if SS Board 3 was used):** tap **SS Board 4
  Undo Firmware Fix**. It removes only the `/lib/ld-linux.so.3` symlink it
  created, and only when it points at `/lib/ld-linux-armhf.so.3`.
- **Remove the whole hack:** use the uninstaller from the same MobileRead
  package (`Update_linkss_0.25.N_uninstall.bin`), or delete `/mnt/us/linkss` and
  reboot. The stock framework then resumes control of the sleep screen.
- **Remove this bundle:** delete `/mnt/us/extensions/screensaver-board/`, the
  seven `ssb-*.sh` files in `/mnt/us/documents/`, and the five `ssb-*.png` files
  in `/mnt/us/dashboard/`. If auto-refresh is enabled, tap **SS Board 7** first
  so the upstart job and its `/etc/init/screensaver-board-refresh.conf` are
  removed. Nothing else changes.

---

## Known limitations and caveats

- **Weak content validation.** Whatever URL you configure is validated only by
  PNG magic bytes and a 2 MiB size cap. There is **no signature**, and if you
  configure a plain `http://` URL there is **no TLS** either - so a network
  attacker could serve a different image, or a truncated one. The size cap and
  the on-device `eips` gate limit the damage but do not authenticate the
  content. Configure an `https://` URL unless you control the whole path.
- **On-device conversion costs time.** Normalising the board with linkss's
  ImageMagick takes a couple of seconds on a PW3. (The exact cost is not
  measured in the repository; it is stated here as an expectation, not a
  benchmark.)
- **Stale log line.** `bin/test-format.sh` prints `See to-png8.sh / README.md`
  on failure, but the host-side helper is `bin/to-png8.py`. The line refers to a
  filename that does not exist.
- **One pool file, always `bg_ss00.png`.** `bin/set-screensaver.sh` always
  installs `/mnt/us/linkss/screensavers/bg_ss00.png` (the FW >= 5.5 final name
  `shuffless` writes). After a verified install it MOVES every other `*.png` in
  the pool to `/mnt/us/dashboard/screensaver-quarantine/` (never deletes), so
  the pool holds exactly one file. Recover a quarantined file by moving it back
  by hand.
- **Live-read assumption is unverified here.** That replacing the already-named
  `bg_ss00.png` in the bind-mounted pool is read at the next sleep without a
  restart is inferred from linkss bind-mounting
  `/mnt/us/linkss/screensavers` onto `/usr/share/blanket/screensaver`, not from
  reading the linkss source. The **first** install still needs a reboot so
  `shuffless` can name the pool files.
- **Upstart job name is detected heuristically.** The installer uses
  `/etc/init/framework.conf` -> `framework`, else `/etc/init/lab126_gui.conf` ->
  `lab126_gui`, else a `start on runlevel [2345]` fallback (with a logged
  warning). A firmware whose main job has a different name would take the
  fallback path.
- **Autostart runs root code from the userstore (accepted risk).** The
  `screensaver-board-refresh` upstart job is started by `init` as root and runs
  `/mnt/us/extensions/screensaver-board/bin/refresh-daemon.sh`, which lives on
  the user-writable `/mnt/us` partition. Anyone with USB write access to the
  Kindle could alter that script and it would run as root at the next boot. This
  is the accepted trade-off of boot autostart with this architecture; tap
  **SS Board 7 Auto-Refresh Off** to remove the job (and reboot) if that is not
  acceptable. The fetch is also plain HTTP with no signature, and the `wget`
  path has no byte cap (only a post-hoc size check); these are accepted,
  documented limitations (see "Weak content validation").
- **Bundle README coverage.** `kindle-device/screensaver-board/README.md` is the
  authoritative reference for the bundle's scripts; this root README and it may
  still differ in wording, but both describe the seven library entries.
- **KUAL route is unusable as-is.** `config.xml` / `menu.json` are shipped, but
  the firmware has no KUAL and no working Kindlet launcher, so the KUAL menu
  cannot be used on this device.

---

## Development notes

- Run `sh -n` on every shell script before deploying. All scripts in
  `kindle-device/` currently pass `sh -n` (POSIX `sh`, busybox/ash-safe, no
  bashisms).
- `kindle-device/screensaver-board/tests/` is a **host-only** harness
  (`sh tests/run.sh`): it syntax-checks the bundle scripts, validates
  `menu.json`, and runs the `lib-pool.sh` quarantine tests. It is **never
  deployed** to the Kindle.
- Files must have **LF** line endings. CRLF breaks the library scriptlets.
- Deployed copies must be **byte-identical** to the repository copies. Compare
  before ejecting, for example `cmp repo/file /media/<kindle>/path/file`.
- `bin/to-png8.py` is the **host-side** Pillow converter (it never runs on the
  Kindle). It writes a clean, exactly 1072x1448, 8-bit PNG with no ICC profile
  and no alpha - grayscale by default, or an 8-bit adaptive palette with
  `--palette`. Pillow is installed on this workstation (verified: Pillow
  12.1.1). ImageMagick is **not** installed on the host; the only ImageMagick
  used is the copy linkss ships on the device.

---

## Credits

- **NiLuJe** - the ScreenSavers (`linkss`) hack and the guidance on rebooting
  unplugged.
- **MRPI (MR Package Installer)** - installing packages from
  `/mnt/us/mrpackages`.
- **MobileRead forums** - hosting the ScreenSavers snapshots and MRPI package.
