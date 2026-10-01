#!/usr/bin/env python3
"""to-png8.py - HOST/DESKTOP-SIDE re-encode helper (run on your PC, not the Kindle).

WHY THIS EXISTS
    The server renders board.png as a palette PNG. NiLuJe's ScreenSavers docs
    warn that low-colour indexed PNGs can make FW 5.x give up on screensavers
    until a reboot. This helper re-encodes the file to a clean, exactly
    1072x1448, 8-bit PNG with no ICC profile and no alpha channel.

WHAT IT DOES
    - Reads an input PNG (PNG only; anything else is rejected).
    - Flattens any transparency onto white.
    - Resizes to exactly 1072x1448 with LANCZOS if the size differs.
    - Writes 8-bit grayscale (mode L) by default, or an 8-bit adaptive
      palette (mode P, 256 colours) when --palette is given.
    - Reads the written file back and prints the dimensions, bit depth,
      colour type and ICC status that are actually on disk.

USAGE
    python3 to-png8.py <input.png> [output.png]
    python3 to-png8.py --palette <input.png> [output.png]

    The output defaults to <input-stem>-png8.png. The input is never
    overwritten unless you pass the same path as output explicitly.

THIS IS NOT A DEVICE ACTION
    It is a desktop helper. It does not run on the Kindle.
"""

import argparse
import os
import struct
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - depends on the host environment
    sys.stderr.write(
        "ERROR: Pillow is not installed, so this helper cannot run.\n"
        "Install it with: python3 -m pip install Pillow\n"
        "Nothing was written.\n"
    )
    raise SystemExit(2)

TARGET_SIZE = (1072, 1448)
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
COLOR_TYPES = {
    0: "grayscale",
    2: "truecolor",
    3: "indexed (palette)",
    4: "grayscale + alpha",
    6: "truecolor + alpha",
}


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="to-png8.py",
        description=(
            "Re-encode a PNG to a clean 8-bit 1072x1448 image with no ICC "
            "profile and no alpha, for the Kindle ScreenSavers hack."
        ),
    )
    parser.add_argument("input", help="input PNG path")
    parser.add_argument(
        "output",
        nargs="?",
        default=None,
        help="output PNG path (default: <input-stem>-png8.png)",
    )
    parser.add_argument(
        "--palette",
        action="store_true",
        help=(
            "write an 8-bit adaptive palette PNG (mode P, 256 colours) "
            "instead of 8-bit grayscale (mode L)"
        ),
    )
    return parser.parse_args(argv)


def fail(message):
    sys.stderr.write("ERROR: %s\n" % message)
    raise SystemExit(1)


def default_output_path(input_path):
    stem, _ = os.path.splitext(input_path)
    return stem + "-png8.png"


def load_clean_rgb(input_path):
    """Open a PNG and return an RGBA-free RGB image (alpha flattened to white)."""
    if not os.path.exists(input_path):
        fail("input not found: %s" % input_path)

    with open(input_path, "rb") as handle:
        head = handle.read(8)
    if head != PNG_MAGIC:
        fail("%s is not a PNG (bad magic bytes)." % input_path)

    with Image.open(input_path) as img:
        if img.format != "PNG":
            fail("%s is a %s file, not a PNG." % (input_path, img.format))

        has_alpha = img.mode in ("RGBA", "LA") or (
            img.mode == "P" and "transparency" in img.info
        )
        if has_alpha:
            rgba = img.convert("RGBA")
            background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            background.alpha_composite(rgba)
            clean = background.convert("RGB")
        else:
            clean = img.convert("RGB")

        if clean.size != TARGET_SIZE:
            clean = clean.resize(TARGET_SIZE, Image.LANCZOS)

    return clean


def force_8bit_palette(pal_img):
    """Pad the palette to a full 256 entries.

    Pillow sizes a palette PNG's bit depth from the number of palette entries,
    so a source with few distinct colours would be written as a 4-bit PNG.
    Padding to 256 entries forces the encoder to emit 8-bit indices, which is
    what a palette PNG8 consumer expects.
    """
    if pal_img.mode != "P":
        return pal_img
    padded = pal_img.copy()
    raw = padded.palette.getdata()[1]
    if len(raw) < 768:
        raw = raw + b"\x00" * (768 - len(raw))
        padded.putpalette(list(raw))
    return padded


def encode(clean, use_palette):
    if use_palette:
        palette_img = clean.convert("P", palette=Image.ADAPTIVE, colors=256)
        return force_8bit_palette(palette_img)
    return clean.convert("L")


def read_png_header(path):
    """Return (width, height, bit_depth, color_type) from the PNG IHDR chunk."""
    with open(path, "rb") as handle:
        header = handle.read(26)
    if len(header) < 26 or header[:8] != PNG_MAGIC:
        fail("written file is not a valid PNG: %s" % path)
    if header[12:16] != b"IHDR":
        fail("first PNG chunk is not IHDR: %s" % path)
    width, height = struct.unpack(">II", header[16:24])
    bit_depth = header[24]
    color_type = header[25]
    return width, height, bit_depth, color_type


def main(argv):
    args = parse_args(argv)
    use_palette = args.palette
    out_path = args.output or default_output_path(args.input)

    if os.path.abspath(out_path) == os.path.abspath(args.input):
        sys.stderr.write(
            "WARNING: output path equals the input path; overwriting the input.\n"
        )

    clean = load_clean_rgb(args.input)
    encoded = encode(clean, use_palette)

    # No pnginfo and no icc_profile argument: metadata is not carried over.
    encoded.save(out_path, format="PNG", optimize=True)

    # --- verify by reading the file back, not by assuming --------------------
    width, height, bit_depth, color_type = read_png_header(out_path)
    with Image.open(out_path) as verify_img:
        icc_present = bool(verify_img.info.get("icc_profile"))
        mode = verify_img.mode
        palette_colours = (
            len(verify_img.getcolors(maxcolors=256) or [])
            if mode == "P"
            else None
        )
        palette_capacity = (
            len(verify_img.palette.getdata()[1]) // 3 if mode == "P" else None
        )

    color_name = COLOR_TYPES.get(color_type, "unknown")
    print("Wrote: %s" % out_path)
    print("Verification (read back from the written file):")
    print("  dimensions : %d x %d" % (width, height))
    print("  bit depth  : %d" % bit_depth)
    print("  colour type: %d (%s)" % (color_type, color_name))
    print("  ICC profile: %s" % ("present" if icc_present else "none"))
    if palette_colours is not None:
        print(
            "  palette    : %d entries, %d colours in use"
            % (palette_capacity, palette_colours)
        )
    # Keep the report ahead of any diagnostics when stdout is piped/block-buffered.
    sys.stdout.flush()

    ok = True
    if (width, height) != TARGET_SIZE:
        sys.stderr.write(
            "ERROR: written image is %dx%d, expected %dx%d.\n"
            % (width, height, TARGET_SIZE[0], TARGET_SIZE[1])
        )
        ok = False
    if bit_depth != 8:
        sys.stderr.write("ERROR: written bit depth is %d, expected 8.\n" % bit_depth)
        ok = False
    if color_type in (4, 6):
        sys.stderr.write("ERROR: written image still has an alpha channel.\n")
        ok = False
    if icc_present:
        sys.stderr.write("ERROR: written image still carries an ICC profile.\n")
        ok = False
    if not ok:
        raise SystemExit(1)

    print("OK: clean 8-bit PNG at %dx%d." % TARGET_SIZE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
