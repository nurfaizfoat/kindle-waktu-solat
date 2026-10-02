# Troubleshooting

Expanded troubleshooting for the Kindle prayer-times screensaver. Every message
quoted below is produced by a script in this repository, so you can match what
you see on the device or in the logs to a cause and a fix.

---

## 1. Where the logs live

All screensaver logs are written under `/mnt/us/dashboard/` so they are readable
over USB. MRPI keeps its own log under its extension directory.

| Log | Written by | Contains |
| --- | --- | --- |
| `/mnt/us/dashboard/screensaver.log` | `refresh.sh`, `set-screensaver.sh`, `test-format.sh`, `prepare-ldsymlink.sh`, `remove-ldsymlink.sh`, `install-refresh-autostart.sh`, `remove-refresh-autostart.sh` | The fetch -> normalise -> gate -> install trace, the firmware-fix trace, and the auto-refresh install/remove trace. |
| `/mnt/us/dashboard/refresh-daemon.log` | `refresh-daemon.sh` | The background daemon's start, each wake/interval, each refresh attempt, and final failures. Rotated to `.1` past 256 KiB. |
| `/mnt/us/dashboard/screensaver-diag.log` | `diagnose.sh` (only) | Full read-only device state: firmware, processes, linkss, `blanket`, lipc props, `ld-linux` symlink. |
| `/mnt/us/extensions/MRInstaller/log/` | MRPI, launched by `ssb-5-install-linkss.sh` | The MRPI install trace. (The directory is named by the scriptlet; the filename `mrinstaller.log` is the conventional one and is **not** asserted by any repository script.) |
| `/mnt/us/dashboard/dashboard.log` | Legacy `dashboard.sh` / `stop-dashboard.sh` | Only if the old framebuffer dashboard is used. |
| `/mnt/us/dashboard/probe.log` | Legacy `probe_power.sh` | Power-event probe output. |
| `/mnt/us/runme.log` | Legacy `RUNME.sh` | `;log runme` trigger output. |

### Reading a log over USB

1. Connect the Kindle to the computer with the USB cable.
2. The userstore mounts as removable storage. The exact mount point depends on
   the OS; on Linux it is typically under `/media/<user>/<volume label>` (the
   exact path is environment-dependent and not fixed by this project).
3. Open the file at the mapped path. For example, on a Kindle volume mounted at
   `/media/<user>/Kindle`:

   - `/mnt/us/dashboard/screensaver.log`
     -> `<mount>/dashboard/screensaver.log`
   - `/mnt/us/dashboard/screensaver-diag.log`
     -> `<mount>/dashboard/screensaver-diag.log`
   - `/mnt/us/extensions/MRInstaller/log/`
     -> `<mount>/extensions/MRInstaller/log/`

4. Copy the log off the device before you eject, if you want to keep it.

Notes:

- While the USB cable is connected, `/mnt/us` is unmounted **on the device**, so
  you cannot run a refresh at the same time; the scripts refuse in that state
  with the mount error in section 2.
- The logs are appended to, so the newest entries are at the bottom. The
  `dmesg`-style `<timestamp>` prefix is `YYYY-MM-DD HH:MM:SS`. The daemon rotates
  `refresh-daemon.log` and `screensaver.log` to `<file>.1` once they pass 256 KiB,
  so read the `.1` predecessor if the current file seems to start mid-story.
- The device-side logs are plain text; any text editor works.
- The on-screen summary printed by a library scriptlet is visible because the
  scriptlets omit the `# DontUseFBInk` line. If you only have the device (no
  PC), that summary carries the exit code and the log path.

---

## 2. Common messages and their meaning

### The board URL is not configured (exit 8)

`refresh.sh` ships with a placeholder URL and refuses to fetch until you point
it at a real deployment:

```
ERROR: the board URL is not configured.
Create /mnt/us/dashboard/board-url.conf with a BOARD_URL line, for example:
    BOARD_URL="https://your-host/path/board.php"
Template: kindle-device/board-url.conf.sample in the repository.
Refusing to fetch until it is configured.
```

Fix: copy `kindle-device/board-url.conf.sample` to
`/mnt/us/dashboard/board-url.conf` and edit the `BOARD_URL` line. `dashboard.sh`
and `test_display.sh` run the same check but exit `1` instead of `8`.

### `/mnt/us` is not mounted

```
ERROR: /mnt/us is not a mounted filesystem - refusing to create /mnt/us/dashboard.
Mount the Kindle userstore and try again.
```

`diagnose.sh` variant:

```
ERROR: /mnt/us is not a mounted filesystem.
Reconnect the Kindle userstore and try again.
```

Cause: the userstore is unmounted - usually USB drive mode is active, or the
mount is wedged.
Fix: eject cleanly on the host and disconnect USB; if it persists, reboot.

### Another instance is already running

```
REFUSING: another refresh is running (pid <pid>).
REFUSING: another set-screensaver is running (pid <pid>).
REFUSING: could not acquire lock /mnt/us/dashboard/refresh.lock.
```

Cause: two library taps raced, or a previous run left a lock with a live PID.
Fix: wait for the running instance to finish; if the PID is stale the lock is
removed and re-acquired automatically. As a last resort, reboot.

### Fetch failed

```
FAIL: fetch failed (network down, server unreachable, or over size cap).
Keeping the existing /mnt/us/dashboard/board.png unchanged.
```

or

```
FAIL: download is <N> bytes, over the 2097152-byte cap - rejected.
```

Cause: no network, the server is down, or the download exceeded the 2 MiB cap.
Fix: confirm Wi-Fi is on and the board URL responds; the previous good board is
kept, so nothing is lost. Retry **SS Board 2 Install Board**.

### The renderer rejected the board

```
<scriptlet>: Result: install did not complete. The previous good board was kept.
```

```
=== refresh start ===
...
FAIL: eips returned <N> - device renderer rejected the PNG
If the screen did not change, re-encode the board to 8-bit first (see to-png8.sh / README.md).
=== test-format done (FAILED) ===
```

```
REFUSING to install: the device renderer rejected this board.
Preserved the previous good board at /mnt/us/dashboard/board.png (not overwritten).
See to-png8.py / README.md for the host-side re-encode.
```

Cause: the fetched PNG was below 8-bit (the server emits a low-bit indexed
PNG). `refresh.sh` normally converts it on-device with linkss's ImageMagick.
Fix: make sure linkss is installed (`/mnt/us/linkss/bin/convert` must exist). If
it is missing you will also see:

```
note: linkss ImageMagick not found - gating the file exactly as fetched
```

Install linkss via **SS Board 5 Install LinksS**, then retry **SS Board 2**.

### The renderer rejected a normalisation candidate

These are informational; the script tries the next candidate:

```
note: the gray candidate was rejected by the renderer
note: the pal8 candidate was rejected by the renderer
```

A success looks like:

```
normalised to 8-bit (gray) and accepted by the renderer
```

### `eips` itself is missing

```
FAIL: /usr/sbin/eips not found or not executable - cannot test on the device
```

Cause: unexpected firmware state; `eips` is the stock renderer.
Fix: this is not something the bundle can repair; verify the firmware has not
been modified.

### linkss is not installed

```
=== set-screensaver start (src=/mnt/us/dashboard/board.png) ===
REFUSING: /mnt/us/linkss does not exist.
The ScreenSavers (linkss) hack must be installed first - see README.md.
```

In `screensaver-diag.log`:

```
=== linkss (ScreenSavers hack) on userstore ===
(missing: /mnt/us/linkss - ScreenSavers hack NOT installed)
```

Cause: the ScreenSavers (linkss) hack is absent or was removed.
Fix: install it (**SS Board 5 Install LinksS** with the package queued in
`/mnt/us/mrpackages`), then reboot unplugged and run **SS Board 1 Diagnose** to
confirm `/mnt/us/linkss` now exists.

### Source board is missing / empty / not a PNG / wrong size

```
FAIL: source file not found: /mnt/us/dashboard/board.png
FAIL: source file is empty: /mnt/us/dashboard/board.png
FAIL: source is not a PNG (magic bytes: '<hex>')
FAIL: source dimensions are '<WxH>', expected 1072x1448 for a PW3.
Refusing to install a wrong-sized screensaver (fail closed).
```

Cause: `board.png` is missing, empty, corrupt, or not 1072x1448.
Fix: run **SS Board 2 Install Board** to fetch a fresh board. If a
`board.png.bak` exists, it is the previous good board.

### More than one screensaver file (board shows only sometimes)

```
quarantined extra screensaver file: /mnt/us/linkss/screensavers/<name>.png -> /mnt/us/dashboard/screensaver-quarantine/<name>.png (moved, not deleted)
WARNING: could not move /mnt/us/linkss/screensavers/<name>.png to /mnt/us/dashboard/screensaver-quarantine; the pool may still cycle.
```

Cause: linkss cycles between multiple `bg_*.png` files, so the board appears on
some sleeps and not others. The usual culprit is the linkss sample
`00_you_can_delete_me-kv.png` if it was not removed.
Fix: run **SS Board 2 Install Board**. After a verified install it moves every
`*.png` other than `bg_ss00.png` into
`/mnt/us/dashboard/screensaver-quarantine/` (recoverable, never deleted), so the
pool holds exactly one file. If a move failed (for example the quarantine dir
could not be created) the WARNING above is logged and the pool may still cycle;
free space on `/mnt/us` or move the extras by hand, then re-run **SS Board 2**.

### Wrong screensaver filename

```
ERROR: installed filename '<name>' is not bg_ss00.png.
linkss reads bg_ssNN.png from the bind-mounted pool; a wrong name would be ignored.
```

Cause: on firmware 5.5 and newer, linkss's `shuffless` names pool files
`bg_ss00.png`, `bg_ss01.png`, ... This bundle owns exactly `bg_ss00.png` and
`set-screensaver.sh` now always installs that final name directly, so a wrong or
legacy name (`bg_large_ss00.png`, `bg_ss01.png`, ...) is either quarantined as an
extra or refused.
Fix: run **SS Board 2 Install Board**. It installs `bg_ss00.png` and quarantines
any other pool file. A legacy `bg_<group>_ssNN.png` written by an older build only
takes effect after a reboot (when `shuffless` renames it); the current script
avoids that delay by writing `bg_ss00.png` itself.

### Rootfs was left read-write

```
restoring rootfs to read-only (mntroot ro)
observed rootfs mount state: rw
ERROR: rootfs is STILL read-write after mntroot ro - REBOOT the device.
```

Cause: `mntroot ro` did not take effect after retries.
Fix: reboot immediately. The scripts return the rootfs to read-only on every
exit path, including failure and signals, so this is the last-resort warning.

### Firmware-fix symlink problems

`prepare-ldsymlink.sh` (SS Board 3):

```
WARNING: /lib/ld-linux.so.3 does not resolve to /lib/ld-linux-armhf.so.3 (resolved='<target>').
Refusing to change it automatically and NOT treating this as success.
Run 'Remove ld symlink (rollback)' first, then re-run this action.
```

```
FAIL: target /lib/ld-linux-armhf.so.3 does not exist - refusing to create a dangling symlink
FAIL: mntroot not found - cannot remount the rootfs read-write
```

`remove-ldsymlink.sh` (SS Board 4):

```
WARNING: /lib/ld-linux.so.3 does not point to /lib/ld-linux-armhf.so.3 - refusing to remove it.
This is not the workaround symlink this bundle creates. Inspect manually.
```

Cause: the symlink is missing, wrong, or points somewhere unexpected; or the
rootfs tooling is unavailable.
Fix: read the `ld-linux symlink (5.17+ workaround check)` section of
`screensaver-diag.log`. A correct state is:

```
/lib/ld-linux.so.3 -> /lib/ld-linux-armhf.so.3
```

If it is dangling or wrong, run **SS Board 4 Undo Firmware Fix** and then
**SS Board 3 Firmware Fix** again.

### MRPI could not run

From `ssb-5-install-linkss.sh`:

```
MRPI not found on this Kindle.
Expected: /mnt/us/extensions/MRInstaller/bin/mrinstaller.sh
Copy extensions/MRInstaller onto the device, then tap this again.
```

```
Package folder missing: /mnt/us/mrpackages
```

```
No packages found in /mnt/us/mrpackages
Copy the linkss .bin in there over USB, then tap this again.
```

```
Result: MRPI did not finish cleanly.
Check its log under /mnt/us/extensions/MRInstaller/log/
```

Cause: MRPI extension missing, the package queue empty, or MRPI errored.
Fix: copy `extensions/MRInstaller/` to `/mnt/us/extensions/`, put the linkss
`.bin` in `/mnt/us/mrpackages/`, then retry. Read the MRPI log.

### MRPI finished but the summary was cut off

```
Result: MRPI finished - the Kindle should restart.
After it restarts unplugged, sleeping should show a screensaver.
```

MRPI normally reboots the device when it finishes, so a truncated summary is
expected, not an error.

### The board shows a stale time / old prayer times

Cause: the board is a **static image**. The Kindle does not redraw it by itself;
the visible board is as fresh as the last successful refresh. If auto-refresh is
not enabled, it is frozen at the moment you last tapped **SS Board 2 Install
Board**. Also, while the device is **asleep no process can run**, so the board
shown on wake is from the last refresh before sleep.

Fix:

1. Confirm auto-refresh is enabled: tap **SS Board 6 Auto-Refresh On** (or check
   that `/etc/init/screensaver-board-refresh.conf` exists). With it enabled the
   daemon refreshes on every wake and at least hourly while the device is awake.
   The cadence is: a sliced 10-second wait, a refresh on each wake debounced to
   at most one per 60s, and an hourly floor while continuously awake.
2. Check `/mnt/us/dashboard/refresh-daemon.log` for the daemon start, each
   wake/interval, and the per-attempt result; check
   `/mnt/us/dashboard/screensaver.log` for the fetch/install trace. Both logs are
   rotated to `<file>.1` once they pass 256 KiB, so read the current file and its
   `.1` predecessor if the newest entries look truncated.
3. Run **SS Board 1 Diagnose** and read the
   `auto-refresh (screensaver-board-refresh)` section: it shows the job file, the
   `initctl status`, the daemon pidfile state, the last 20 lines of
   `refresh-daemon.log`, and whether `board-url.conf` exists.
4. Wake the device (open the cover or press power) so a refresh can run; if the
   server is unreachable, the previous board is kept and the daemon retries on
   the next cycle (a refresh.sh exit 8, "board URL not configured", is permanent
   and is not retried - create `board-url.conf` first).
5. To refresh immediately, tap **SS Board 2 Install Board**.

To turn automatic refreshing off, tap **SS Board 7 Auto-Refresh Off**.

### Nothing happens when tapping a library entry

Cause: the library has not rescanned after files were copied.
Fix: eject and reconnect USB, or restart the device. Confirm the scriptlets and
icons landed at `/mnt/us/documents/` and `/mnt/us/dashboard/ssb-*.png`.

---

## 3. Symptom-to-fix quick table

| Symptom | Cause | Fix |
| --- | --- | --- |
| Stock/default screensaver appears instead of the board. | `linkss/screensavers/` is empty, so linkss disables itself. | Run **SS Board 2 Install Board**, then reboot unplugged. |
| `eips: paint_image> cannot open "...":8bit only`. | The fetched PNG was below 8-bit. | `refresh.sh` normalises on-device with linkss's ImageMagick; if it is missing, install linkss (**SS Board 5**). |
| Board appears only SOME of the time. | More than one PNG in `linkss/screensavers/`; linkss cycles. | Run **SS Board 2 Install Board**; it moves every extra `*.png` to `/mnt/us/dashboard/screensaver-quarantine/` (recoverable), leaving exactly one. |
| MRPI install greyed out or fails. | Missing 5.17+ `/lib/ld-linux.so.3` symlink. | Run **SS Board 3 Firmware Fix**, reboot unplugged, retry. |
| Nothing happens when tapping. | Library needs a rescan. | Eject/reconnect USB, or restart. |
| Install looks fine but screensavers never change. | Framework not restarted after the first install (shuffless must name the pool files). | Reboot the first time, always with the device **UNPLUGGED**; later refreshes of the correctly-named `bg_ss00.png` are read at the next sleep. |
| The board shows a stale time / old prayer times. | The board is a static image and auto-refresh is off (or the device was asleep). | Enable auto-refresh (**SS Board 6**); it refreshes on wake and at least hourly while awake. See `/mnt/us/dashboard/refresh-daemon.log`. |
| Log ends at `FAIL: fetch failed ...`. | Network or server unavailable. | Check Wi-Fi and the board URL; retry **SS Board 2**. |
| `board.png` is stale after midnight. | `board.php` caches a render for up to 60 seconds. | Wait a minute, then refresh. |

---

## 4. Exit-code reference

`refresh.sh`

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | Fetch failed (network/server/size cap) - previous board kept. |
| 2 | Could not back up `board.png`/move it into place, OR propagated from `set-screensaver.sh` (linkss missing or a bad source). |
| 3 | The device renderer rejected the board - previous board kept (refresh.sh's own rejection). |
| 4 | `set-screensaver.sh` is missing. |
| 5 | Propagated from `set-screensaver.sh`: failed to move the file into place. |
| 6 | Propagated from `set-screensaver.sh`: installed file missing/empty or IHDR not 1072x1448. |
| 7 | Propagated from `set-screensaver.sh`: installed basename is not `bg_ss00.png`. |
| 8 | The board URL is not configured (`/mnt/us/dashboard/board-url.conf` missing/placeholder). Permanent: the daemon does not retry it. |
| 9 | Another instance holds the lock. |
| 10 | `/mnt/us` is not a mount. |

`set-screensaver.sh`

| Code | Meaning |
| --- | --- |
| 0 | Installed and verified (extras quarantined). |
| 2 | `/mnt/us/linkss` missing, `lib-pool.sh` missing, or source missing/empty/not PNG/wrong size. |
| 3 | Could not create the screensaver directory. |
| 4 | Copy to the temp file failed. |
| 5 | Move into place failed. |
| 6 | Installed file missing/empty or IHDR not 1072x1448. |
| 7 | Installed basename is not exactly `bg_ss00.png`. |
| 9 | Another instance holds the lock. |
| 10 | `/mnt/us` is not a mount. |

`prepare-ldsymlink.sh` / `remove-ldsymlink.sh`

| Code | Meaning |
| --- | --- |
| 0 | Done (created, already correct, or nothing to remove). |
| 2 | `/lib` missing, `mntroot` missing, or symlink target missing. |
| 4 | `ln -s` / `rm` reported failure. |
| 5 | Verification after the change failed. |
| 6 | The existing symlink is wrong or foreign - refused. |
| 7 | Rootfs still read-write after `mntroot ro` - reboot. |
| 10 | `/mnt/us` is not a mount. |

`test-format.sh`

| Code | Meaning |
| --- | --- |
| 0 | `eips` accepted the PNG. |
| 1 | `eips` rejected the PNG. |
| 2 | File missing/empty/not PNG/wrong size, or IHDR unreadable. |
| 3 | `/usr/sbin/eips` not executable. |
| 10 | `/mnt/us` is not a mount. |

---

## 5. Diagnostic sweep

When you are unsure what is wrong:

1. Tap **SS Board 1 Diagnose**.
2. Copy `/mnt/us/dashboard/screensaver-diag.log` over USB.
3. Check these sections:

   - `=== firmware version ===` - the device should report the expected
     firmware.
   - `=== linkss (ScreenSavers hack) on userstore ===` - `/mnt/us/linkss` and
     `/mnt/us/linkss/screensavers` should be listed.
   - `=== blanket screensaver (rootfs) ===` - `/usr/share/blanket` and
     `/usr/share/blanket/screensaver` should be readable.
   - `=== lipc powerd properties ===` - `preventScreenSaver` should be `0` in
     normal use.
   - `=== ld-linux symlink (5.17+ workaround check) ===` - expected result after
     the fix: `/lib/ld-linux.so.3 -> /lib/ld-linux-armhf.so.3`.
4. Then tap **SS Board 2 Install Board** and read
   `/mnt/us/dashboard/screensaver.log`.

Remember: `diagnose.sh` is read-only apart from its own log, so it is always
safe to run first.
