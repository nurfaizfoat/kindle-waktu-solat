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
| `/mnt/us/dashboard/screensaver.log` | `refresh.sh`, `set-screensaver.sh`, `test-format.sh`, `prepare-ldsymlink.sh`, `remove-ldsymlink.sh` | The fetch -> normalise -> gate -> install trace, plus the firmware-fix trace. |
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
- The logs are appended to, not rotated, so the newest entries are at the
  bottom. The `dmesg`-style `<timestamp>` prefix is `YYYY-MM-DD HH:MM:SS`.
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
WARNING: other screensaver files exist and are NOT managed by this bundle:
    /mnt/us/linkss/screensavers/<name>.png
WARNING: extras can cause unpredictable cycling in linkss.
Remove them manually if you want exactly one screensaver.
```

Cause: linkss cycles between multiple `bg_*.png` files, so the board appears on
some sleeps and not others. The usual culprit is the linkss sample
`00_you_can_delete_me-kv.png` if it was not deleted.
Fix: delete every screensaver file except the one the bundle owns
(`bg_large_ss00.png`), then reboot unplugged. The installer deliberately never
deletes files it did not create.

### Wrong panel group

```
WARNING: screensaver files for a DIFFERENT panel group exist and will be IGNORED:
    /mnt/us/linkss/screensavers/bg_medium_ss00.png
WARNING: linkss only reads the 'large' group on this 1072x1448 panel.
```

or, if the installed filename is wrong:

```
ERROR: installed filename group is '<group>', expected 'large'.
linkss would ignore '<name>' on this 1072x1448 panel.
```

Cause: a 1072x1448 PW3 panel uses the linkss group `large`; files for another
group are not the right ones for this panel.
Fix: keep only `bg_large_ss00.png`.

> Caveat: `set-screensaver.sh` says other-group files "will be IGNORED", while
> its own extras warning says other files can cause cycling. The exact linkss
> behaviour for other-group files is **unverified**. Keeping exactly one file
> avoids both outcomes.

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
| Board appears only SOME of the time. | More than one PNG in `linkss/screensavers/`; linkss cycles. | Keep exactly one file; delete extras (including the linkss sample `00_you_can_delete_me-kv.png`). |
| MRPI install greyed out or fails. | Missing 5.17+ `/lib/ld-linux.so.3` symlink. | Run **SS Board 3 Firmware Fix**, reboot unplugged, retry. |
| Nothing happens when tapping. | Library needs a rescan. | Eject/reconnect USB, or restart. |
| Install looks fine but screensavers never change. | Framework not restarted after install/update. | Reboot, always with the device **UNPLUGGED**. |
| Log ends at `FAIL: fetch failed ...`. | Network or server unavailable. | Check Wi-Fi and the board URL; retry **SS Board 2**. |
| `board.png` is stale after midnight. | `board.php` caches a render for up to 60 seconds. | Wait a minute, then refresh. |

---

## 4. Exit-code reference

`refresh.sh`

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | Fetch failed (network/server/size cap) - previous board kept. |
| 2 | Could not back up `board.png`, or could not move the file into place. |
| 3 | The device renderer rejected the board - previous board kept. |
| 4 | `set-screensaver.sh` is missing. |
| 9 | Another instance holds the lock. |
| 10 | `/mnt/us` is not a mount. |

`set-screensaver.sh`

| Code | Meaning |
| --- | --- |
| 0 | Installed and verified. |
| 2 | `/mnt/us/linkss` missing, or source missing/empty/not PNG/wrong size. |
| 3 | Could not create the screensaver directory. |
| 4 | Copy to the temp file failed. |
| 5 | Move into place failed. |
| 6 | Installed file missing/empty or IHDR not 1072x1448. |
| 7 | Installed filename's panel group is wrong. |
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
