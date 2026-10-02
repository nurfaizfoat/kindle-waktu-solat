# Screensaver Board (native Kindle screensaver)

Turns the rendered prayer board into the Kindle's **native** screensaver: close
the lid and the board shows; open the lid and reading resumes. This replaces the
framebuffer-takeover dashboard approach, which let the stock clock/battery
chrome draw over the board.

- Target: Kindle Paperwhite 3 (7th gen), firmware **5.16.2.1.1**, jailbroken.
- Board source: `https://example.com/waktu/board.php` (placeholder - set your own
  URL in `/mnt/us/dashboard/board-url.conf`, using `board-url.conf.sample` as a
  template)
- Screensaver engine: NiLuJe's **ScreenSavers (linkss)** hack.

> **WARNING - Special Offers must be disabled first.**
> If the device still shows Special Offers (ads), the ScreenSavers hack will
> **not** work: the ad framework owns the sleep screen and overrides it. Disable
> Special Offers (your ad-remover script) and confirm the lock screen is ad-free
> **before** starting this procedure.

> **WARNING - plain HTTP.**
> The board is fetched over plain `http://` and validated only by PNG magic
> bytes and a size cap. There is no TLS and no signature, so a network attacker
> could serve a different image, or a truncated one. The size cap and the
> on-device `eips` gate limit the damage but do not authenticate the content. If
> that matters to you, host the board over HTTPS and set `BOARD_URL` to it in
> `/mnt/us/dashboard/board-url.conf`.

Everything here is additive. It does not modify `dashboard.sh`, the running
dashboard, KOReader, or any pre-existing file.

---

## How you launch this on this device

This firmware has **no KUAL and no working Kindlet launcher**. The only launcher
is **library scriptlets**: a `.sh` file in `/mnt/us/documents/` whose header has
`# Name:`, `# Author:` and `# Icon:`. The Kindle shows it in the library as a
tappable book.

That is why this bundle ships seven library entries. **Tap them in numeric
order.** Each one prints a short summary on the device screen (exit code, a
plain-English verdict, and the log path), so you can read the result without a
PC. The scriptlets deliberately do **not** carry a `# DontUseFBInk` line, so the
on-screen output is visible.

| Library entry | Runs | Writes |
| --- | --- | --- |
| **SS Board 1 Diagnose** | `bin/diagnose.sh` (read-only) | `/mnt/us/dashboard/screensaver-diag.log` |
| **SS Board 2 Install Board** | `bin/refresh.sh` (fetch, gate, install) | `/mnt/us/dashboard/screensaver.log` |
| **SS Board 3 Firmware Fix** | `bin/prepare-ldsymlink.sh` (5.17+ workaround) | `/mnt/us/dashboard/screensaver.log` |
| **SS Board 4 Undo Firmware Fix** | `bin/remove-ldsymlink.sh` (rollback) | `/mnt/us/dashboard/screensaver.log` |
| **SS Board 5 Install LinksS** | runs MRPI `./bin/mrinstaller.sh launch_installer` | `/mnt/us/extensions/MRInstaller/log/` |
| **SS Board 6 Auto-Refresh On** | `bin/install-refresh-autostart.sh` (upstart job) | `/mnt/us/dashboard/screensaver.log` |
| **SS Board 7 Auto-Refresh Off** | `bin/remove-refresh-autostart.sh` (rollback) | `/mnt/us/dashboard/screensaver.log` |

---

## Layout

Repo layout, with where each part goes on the device:

```
screensaver-board/
  config.xml                 KUAL 2.x metadata      -> /mnt/us/extensions/screensaver-board/
  menu.json                  KUAL 2.x menu (secondary route; see below)
  README.md                  this file
  bin/diagnose.sh            read-only diagnostic
  bin/prepare-ldsymlink.sh   5.17+ workaround; guarded mntroot rw/ro
  bin/remove-ldsymlink.sh    rollback of that workaround; guarded mntroot rw/ro
  bin/test-format.sh         draws the PNG with /usr/sbin/eips (cheap gate)
  bin/set-screensaver.sh     installs exactly ONE screensaver (bg_ss00.png)
  bin/lib-pool.sh            SOURCED helper: quarantine non-bg_ss00.png pool files
  bin/refresh.sh             fetch board -> gate -> set screensaver
  bin/refresh-daemon.sh      refresh on wake + at least hourly while awake
  bin/install-refresh-autostart.sh  install the upstart job; guarded mntroot rw/ro
  bin/remove-refresh-autostart.sh   rollback the upstart job; guarded mntroot rw/ro
  bin/to-png8.py             HOST-SIDE re-encode to a clean 8-bit PNG (PC only)
  documents/                 library scriptlet launchers -> /mnt/us/documents/
    ssb-1-diagnose.sh
    ssb-2-install.sh
    ssb-3-fix-ld.sh
    ssb-4-undo-ld.sh
    ssb-5-install-linkss.sh
    ssb-6-autostart-on.sh
    ssb-7-autostart-off.sh
  icons/                     library thumbnails      -> /mnt/us/dashboard/
    ssb-1-diagnose.png
    ssb-2-install.png
    ssb-3-fix-ld.png
    ssb-4-undo-ld.png
    ssb-5-install-linkss.png
    ssb-6-autostart-on.png
    ssb-7-autostart-off.png
  tests/                     HOST-ONLY test harness (never deployed)
    run.sh
    test-pool.sh
```

Shared log: `/mnt/us/dashboard/screensaver.log`
Daemon log: `/mnt/us/dashboard/refresh-daemon.log` (rotated to `.1` past 256 KiB)
Diagnostic log: `/mnt/us/dashboard/screensaver-diag.log`
Quarantine dir: `/mnt/us/dashboard/screensaver-quarantine/` (pool extras, recoverable)

Copy the bundle to the device over USB:

1. `extensions/screensaver-board/` -> `/mnt/us/extensions/screensaver-board/`
2. `documents/*.sh` -> `/mnt/us/documents/`
3. `icons/*.png` -> `/mnt/us/dashboard/`

The icons are already what the `# Icon:` lines point at
(`/mnt/us/dashboard/ssb-*.png`), so each of the seven library entries shows its
own numbered thumbnail (`ssb-1-diagnose.png` ... `ssb-7-autostart-off.png`). You
may need to let the Kindle rescan the library (or reboot) before new entries
appear; a library entry whose `# Icon:` file is missing or shared with another
entry can fail to show.

---

## Primary procedure - scriptlet route

### Step 1 - Re-encode the board to a clean 8-bit PNG (on your PC)

The server currently emits a **palette** PNG. NiLuJe's docs warn that low-colour
indexed PNGs can make FW 5.x give up on screensavers until reboot, so re-encode
before installing. The converter is Python 3 + Pillow (no ImageMagick needed).

```sh
# in this repo, on the host:
python3 bin/to-png8.py ../dashboard/out/board.png
# -> writes ../dashboard/out/board-png8.png
```

By default it writes 8-bit **grayscale** (`L`), exactly 1072x1448, no ICC profile
and no alpha. If a consumer needs a palette PNG8 instead, add `--palette` for an
8-bit adaptive palette (`P`, 256 entries):

```sh
python3 bin/to-png8.py --palette ../dashboard/out/board.png
```

After writing, the script reads the file back and prints what is actually on
disk (dimensions, bit depth, colour type, ICC status) and exits non-zero if any
of those is wrong. It never overwrites the input unless you pass the same path
as output explicitly; the default output is `<input-stem>-png8.png`.

Then copy the encoded file to the device as `/mnt/us/dashboard/board.png` and
run the on-device format test:

1. Copy `board-png8.png` over USB to `Kindle/dashboard/board.png`.
2. On the Kindle: tap **SS Board 1 Diagnose** first, then run the test gate.
   (The gate also runs automatically inside **SS Board 2 Install Board** before
   it replaces anything.)
3. Read `/mnt/us/dashboard/screensaver.log`. You want `PASS: device renderer
   accepted the PNG (eips exit 0)`. If it fails, do **not** continue.

> Note: on firmware 5.5 and newer, linkss's `shuffless` names pool files
> `bg_ss00.png`, `bg_ss01.png`, ... (its `ss_prefix` is `bg_ss`). The older
> `bg_<group>_ss<NN>` name (for example `bg_large_ss00.png`) is only the
> boot-time form that `shuffless` renames. `set-screensaver.sh` therefore
> installs the **final** name `bg_ss00.png` directly, so a refresh is read live
> at the next sleep without a framework restart. After a verified install it
> MOVES every other `*.png` in the pool to
> `/mnt/us/dashboard/screensaver-quarantine/` (recoverable, never deleted), so
> the pool ends with exactly one file. The destination filename is written to
> the log.

### Step 2 - Install the ScreenSavers (linkss) hack

MRPI is **not currently installed** on this device (only `extensions/koreader`
exists). This part still needs a PC and the device search bar; the scriptlets
cannot install it for you.

1. Install MRPI (one-time), if needed:
   - Copy `MRInstaller` / `update_mrpi_installer.bin` to the Kindle drive root
     (`/mnt/us`), eject, and on the device trigger the installer from the
     search bar with `;log mrpi` (or `;log mrpi_install`). Reboot when done.
   - Confirm `extensions/MRInstaller/` appears after the reboot.
2. Download the **ScreenSavers hack** for Kindle from the MobileRead
   **"Kindle ScreenSavers" / Snapshots** thread. This requires a logged-in
   MobileRead forum session, so it cannot be fetched automatically here.
   Pick the current `update_<name>_install.bin` for the Kindle 5.x family.
3. Copy that `.bin` to the Kindle drive root (`/mnt/us`).
4. Eject, then on the device run **`;log mrpi`** from the search bar to let MRPI
   install it. The device reboots when finished.
5. Reconnect USB, then tap **SS Board 1 Diagnose** and read
   `/mnt/us/dashboard/screensaver-diag.log`. Confirm `/mnt/us/linkss` now exists.

> **After installing (or updating) linkss the framework must be restarted, or
> the device fully rebooted, before the hack reads the screensaver pool.**
> NiLuJe's guidance is that the device must be **unplugged from USB while
> rebooting**.

If the MRPI install appears to succeed but screensavers never change, go to
Step 3.

### Step 3 - Stop the old framebuffer dashboard FIRST

Do this **before** verifying the native screensaver. The old dashboard sets
`preventScreenSaver 1` and stops the framework, which suppresses the native
screensaver entirely. If it is still running, the native screensaver will look
broken even when it is installed correctly.

1. Tap the existing **Stop Waktu Solat** library entry, or create
   `/mnt/us/dashboard/stop` over USB. Confirm the framework returns.
2. Remove the library launchers that start it: the `Waktu Solat` /
   `Stop Waktu Solat` documents and their `icon.png` / `stop-icon.png`.
3. `dashboard.sh`, `test_display.sh`, `waktu-solat.sh`, `stop-dashboard.sh` and
   `RUNME.sh` are then inert; archive or delete them at your discretion.
4. Keep `/mnt/us/dashboard/board.png` if you want a local copy, or let
   **SS Board 2 Install Board** manage it.

### Step 4 - Apply the 5.17+ firmware fix (only if Step 2 failed)

The classic linkss hack is confirmed on 5.12.2 and reported broken on 5.17+,
fixed with a missing loader symlink. 5.16.2.1.1 is untested, so run this **only
if** the hack does not work:

- Kindle: tap **SS Board 3 Firmware Fix**.

This refuses to create a dangling link if the target is missing, and **always
returns the rootfs to read-only** even on failure. It only treats
`/lib/ld-linux.so.3` as already done when it resolves to
`/lib/ld-linux-armhf.so.3`; a dangling or wrong link is reported and left
untouched instead of being silently accepted. Verify from the diagnostic log
(tap **SS Board 1 Diagnose** again):

- `ld-linux symlink (5.17+ workaround check)` should now show
  `/lib/ld-linux.so.3 -> /lib/ld-linux-armhf.so.3`.

> **After running this workaround the framework must be restarted, or the device
> fully rebooted, and the device must be unplugged while rebooting** (same
> guidance as Step 2).

### Step 5 - Set the board as the screensaver

Tap **SS Board 2 Install Board**. It fetches the latest board into a temp file,
tests it with the device renderer, and only then replaces `board.png` and
installs it under `/mnt/us/linkss/screensavers/` (named `bg_ss00.png`, the
FW >= 5.5 final name, as described in Step 1). A failed fetch or a failed format
gate leaves the previous good board untouched.

If you prefer to install an existing local board without fetching, use the
secondary KUAL action **Set board as screensaver** (see below).

Both routes refuse to run if `/mnt/us` is not mounted or if `/mnt/us/linkss` is
missing, and say so clearly. Before the first overwrite of an existing
destination, a backup is written to `<dest>.bak` (the backup is kept, not
refreshed, so it always holds the file that was there first). After the install
is verified, every other `*.png` in the pool is moved to
`/mnt/us/dashboard/screensaver-quarantine/` (recoverable, never deleted) so the
pool holds exactly one screensaver.

> **The restart/reboot note applies to the FIRST install, not to every refresh.**
> On the first install `shuffless` must run so linkss names the pool files. But
> linkss bind-mounts `/mnt/us/linkss/screensavers` onto
> `/usr/share/blanket/screensaver`, so once the pool file is correctly named
> `bg_ssNN.png`, replacing its contents is read at the **next sleep** with no
> framework restart. After the first install, reboot unplugged; afterwards a
> refresh needs no reboot.

### Step 6 - Verify

1. Close the lid (or press power to sleep). The board should appear.
2. Open the lid. The normal reading UI should return.
3. Repeat once. It should be deterministic - there is only one screensaver file.

Check `/mnt/us/dashboard/screensaver.log` if it does not behave. Remember Step 3:
a running dashboard will suppress the native screensaver.

### Step 7 - Rollback

- **Remove just the custom board:** delete the installed
  `/mnt/us/linkss/screensavers/bg_ss00.png` and reboot. If a
  `bg_ss00.png.bak` exists, restore it first
  (`mv bg_ss00.png.bak bg_ss00.png`) to get the previous file
  back. The device falls back to the stock screensaver set. Files set aside
  during install are recoverable from
  `/mnt/us/dashboard/screensaver-quarantine/` (move one back by hand if needed).
- **Stop the background auto-refresh:** tap **SS Board 7 Auto-Refresh Off**. It
  stops the daemon and removes the upstart job, leaving the current board in
  place.
- **Remove the firmware fix (only if Step 4 was used):** tap **SS Board 4 Undo
  Firmware Fix**. It removes only that one symlink, and only when it points at
  `/lib/ld-linux-armhf.so.3`. On 5.17+ removing it will break linkss again.
- **Remove the whole hack:** use the uninstaller from the same MobileRead
  package (or delete `/mnt/us/linkss` and reboot). The stock framework then
  resumes control of the sleep screen.
- **Remove this bundle:** delete `/mnt/us/extensions/screensaver-board/`, the
  seven `ssb-*.sh` files in `/mnt/us/documents/`, and the five `ssb-*.png` files
  in `/mnt/us/dashboard/`. Nothing else changes.

---

## Auto-refresh (wake + hourly)

After the manual setup above, the board is still static until you tap **SS Board
2**. The auto-refresh add-on keeps it current in the background:

- **Enable:** tap **SS Board 6 Auto-Refresh On**. It writes the upstart job
  `/etc/init/screensaver-board-refresh.conf` (atomically, inside a guarded
  `mntroot rw`/`ro` block), reloads upstart and starts the job. It is
  idempotent: a byte-identical job file is not rewritten. The job declares
  `kill timeout 30` so the daemon's trap can run on stop.
- **What runs:** `bin/refresh-daemon.sh`, installed by the job as
  `exec /bin/sh /mnt/us/extensions/screensaver-board/bin/refresh-daemon.sh`. The
  daemon refreshes once ~10s after it starts, then loops in **sliced** waits of
  at most 10s each and refreshes after a wake event (debounced to at most one
  per 60s) and otherwise at least every hour while the device stays awake. If
  `lipc-wait-event` is missing - or returns suspiciously fast several times in a
  row - it falls back to the sleep-based hourly timer. If `/mnt/us` is unmounted
  it waits 60s and retries instead of exiting.
- **Retries:** each cycle calls `refresh.sh` up to 3 times, 20s apart (wrapped in
  `timeout 300` when available), to absorb the few seconds Wi-Fi needs to settle
  after a wake. Exit 8 (board URL not configured) is permanent and is not
  retried. The loop never aborts: a failed refresh keeps the previous board
  (`refresh.sh` guarantees that).
- **Asleep has no clock:** while the device is **asleep no process can run**, so
  the board you see is as fresh as the last refresh before sleep. The daemon
  cannot refresh during sleep; it refreshes as soon as the device wakes.
- **Rollback:** tap **SS Board 7 Auto-Refresh Off**. It stops the upstart job
  first, then the daemon, and removes the job file inside a guarded
  `mntroot rw`/`ro` block. It is safe to run when nothing was installed.
- **Logs:** `/mnt/us/dashboard/refresh-daemon.log` (daemon lifecycle and
  attempts) and `/mnt/us/dashboard/screensaver.log` (the fetch/install trace).
  Both rotate to `<file>.1` past 256 KiB.
- **Diagnostics:** **SS Board 1 Diagnose** now includes an
  `auto-refresh (screensaver-board-refresh)` section: the job file, `initctl
  status`, the daemon pidfile state, the last 20 lines of `refresh-daemon.log`,
  and whether `board-url.conf` exists (its contents are not printed).

The daemon never stops or touches the framework, and it uses a single-instance
lock directory plus pidfile with a live-PID and cmdline check, so a stale lock
cannot block a restart.

---

## Converter internals - `bin/to-png8.py`

Host-side Python 3 + Pillow helper. It is **not** a device action and never runs
on the Kindle.

- Input: PNG only (verified by magic bytes and by Pillow's detected format).
  Anything else fails loudly and writes nothing.
- Transparency is flattened onto white.
- Resized to exactly 1072x1448 with LANCZOS only if the size differs.
- Output is a clean 8-bit image with no ICC profile and no alpha.
  - Default: 8-bit grayscale (`L`).
  - `--palette`: 8-bit adaptive palette (`P`), padded to a full 256-entry
    palette so Pillow writes 8-bit indices (without the padding Pillow would
    emit a 4-bit palette PNG for low-colour sources).
- The written file is read back and its dimensions, bit depth, colour type and
  ICC status are printed; it exits non-zero if any of them is wrong.
- The input is never overwritten unless the same path is passed as output
  explicitly. Default output: `<input-stem>-png8.png`.

If Pillow is missing the helper says so and writes nothing
(`python3 -m pip install Pillow`).

---

## Secondary route - the KUAL / Mesquito menu

The bundle also carries a KUAL 2.x extension (`extensions/screensaver-board/`
with `config.xml` + `menu.json`). **This is not usable on this device as-is**,
because the firmware has no KUAL and no working Kindlet launcher. It is kept so
the same bundle still works if a launcher (KUAL or a Mesquito helper) is
installed later.

If a launcher becomes available, the menu mirrors the scriptlets:

- Screensaver Board
  - Diagnose (read-only)
  - Prepare ld symlink (5.17+ fix)
  - Remove ld symlink (rollback)
  - Test PNG format (eips)
  - Refresh board from server
  - Set board as screensaver
  - Enable auto-refresh (boot)
  - Disable auto-refresh (rollback)

Until then, use the library scriptlets above.

---

## Constraints honoured

- POSIX `sh` only (busybox/ash-safe). No bashisms.
- Every script logs to `/mnt/us/dashboard/` so results are readable over USB.
- Scripts refuse to fabricate `/mnt/us/dashboard` when `/mnt/us` is not mounted.
- The scriptlets never fail hard when the bundle is absent: they print a clear
  on-screen message instead.
- The only rootfs writes are inside guarded `mntroot rw` / `mntroot ro` blocks:
  `prepare-ldsymlink.sh`, `remove-ldsymlink.sh`,
  `install-refresh-autostart.sh`, and `remove-refresh-autostart.sh`. Each sets
  the writable flag before `mntroot rw` and returns the rootfs to read-only on
  every exit path, including signals.
- The refresh daemon never stops or touches the framework, uses a single-instance
  lock directory plus pidfile (live-PID plus cmdline check), and keeps the
  previous board on a failed refresh. It waits and retries, rather than exiting,
  when `/mnt/us` is unmounted.
- `diagnose.sh` writes exactly one file and nothing else.
- No pre-existing file is modified. `set-screensaver.sh` never deletes `bg_*.png`
  files it did not create: every pool file other than `bg_ss00.png` is MOVED to
  `/mnt/us/dashboard/screensaver-quarantine/` (recoverable).
- `tests/` is host-only and is never deployed to the Kindle.
- **Accepted risk (autostart).** The `screensaver-board-refresh` upstart job runs
  as root at boot and executes `refresh-daemon.sh` from the user-writable
  `/mnt/us` partition, so anyone with USB write access could alter it. This is
  the accepted trade-off of the user's chosen boot autostart; **SS Board 7
  Auto-Refresh Off** removes the job. The board fetch is also plain HTTP with no
  signature and the `wget` path has no byte cap (only a post-hoc size check);
  these are accepted, documented limitations.
