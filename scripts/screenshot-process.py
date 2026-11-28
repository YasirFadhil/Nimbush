#!/usr/bin/env python3
"""
Nimbush Screenshot Backend
Handles screen capture (grim), coordinate-accurate cropping (ImageMagick),
Xcursor pointer extraction & compositing, clipboard (wl-copy), Swappy, and saving.
"""

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from datetime import datetime
from pathlib import Path

NOTIF_APP = "Screenshot"
NOTIF_ICON = "swappy"
CURSOR_ENV_FILE = Path.home() / ".config/quickshell/state/cursor-theme.env"


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "-a", NOTIF_APP, "-i", NOTIF_ICON, title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def get_image_size(path: Path) -> tuple[int, int]:
    """Read PNG width and height from IHDR chunk without spawning external tools."""
    with open(path, "rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a valid PNG file: {path}")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def read_cursor_config() -> tuple[str, int]:
    """Resolve active XCURSOR_THEME and XCURSOR_SIZE."""
    theme = os.environ.get("XCURSOR_THEME", "").strip()
    size_str = os.environ.get("XCURSOR_SIZE", "").strip()

    if CURSOR_ENV_FILE.is_file():
        for line in CURSOR_ENV_FILE.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line.startswith("XCURSOR_THEME=") and not theme:
                theme = line.split("=", 1)[1].strip().strip("\"'")
            elif line.startswith("XCURSOR_SIZE=") and not size_str:
                size_str = line.split("=", 1)[1].strip().strip("\"'")

    if not theme:
        default_index = Path.home() / ".icons/default/index.theme"
        if default_index.is_file():
            for line in default_index.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.strip().startswith("Inherits="):
                    theme = line.split("=", 1)[1].strip()
                    break

    try:
        size = int(size_str) if size_str else 24
    except ValueError:
        size = 24

    return theme or "Adwaita", max(16, min(size, 128))


def find_xcursor_file(theme: str) -> Path | None:
    """Locate the left_ptr (or default) Xcursor binary for the given theme."""
    search_roots = [
        Path.home() / ".icons",
        Path.home() / ".local/share/icons",
        Path(f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share/icons"),
        Path("/run/current-system/sw/share/icons"),
        Path("/usr/share/icons"),
    ]
    themes_to_try = [theme, "default", "Adwaita", "breeze_cursors"]
    cursor_names = ["left_ptr", "default", "arrow", "top_left_arrow"]

    for t in themes_to_try:
        if not t:
            continue
        for root in search_roots:
            cursors_dir = root / t / "cursors"
            if not cursors_dir.is_dir():
                continue
            for cname in cursor_names:
                candidate = cursors_dir / cname
                if candidate.is_file():
                    return candidate
    return None


def parse_xcursor_to_png(cursor_path: Path, target_size: int, out_png: Path) -> tuple[int, int] | None:
    """
    Parse an Xcursor binary file, pick the frame closest to target_size,
    write it as an RGBA PNG (un-premultiplying alpha), and return (hotspot_x, hotspot_y).
    """
    data = cursor_path.read_bytes()
    if len(data) < 16 or data[:4] != b"Xcur":
        return None

    _, header_size, _, ntoc = struct.unpack_from("<4sIII", data, 0)
    toc_offset = header_size
    image_entries = []

    for i in range(ntoc):
        off = toc_offset + i * 12
        if off + 12 > len(data):
            break
        chunk_type, chunk_subtype, chunk_pos = struct.unpack_from("<III", data, off)
        if chunk_type == 0xFFFD0002:  # XCURSOR_IMAGE_TYPE
            image_entries.append((chunk_subtype, chunk_pos))

    if not image_entries:
        return None

    # Pick entry closest to target_size
    _, best_pos = min(image_entries, key=lambda e: abs(e[0] - target_size))
    if best_pos + 36 > len(data):
        return None

    _, _, _, _, width, height, xhot, yhot, _ = struct.unpack_from("<9I", data, best_pos)
    pixel_offset = best_pos + 36
    expected_bytes = width * height * 4
    if width == 0 or height == 0 or pixel_offset + expected_bytes > len(data):
        return None

    # Xcursor stores premultiplied ARGB in little-endian (B, G, R, A bytes)
    raw_pixels = data[pixel_offset : pixel_offset + expected_bytes]
    rgba = bytearray(expected_bytes)
    for i in range(0, expected_bytes, 4):
        b, g, r, a = raw_pixels[i], raw_pixels[i + 1], raw_pixels[i + 2], raw_pixels[i + 3]
        if a > 0 and a < 255:
            r = min(255, (r * 255) // a)
            g = min(255, (g * 255) // a)
            b = min(255, (b * 255) // a)
        rgba[i] = r
        rgba[i + 1] = g
        rgba[i + 2] = b
        rgba[i + 3] = a

    write_rgba_png(out_png, width, height, bytes(rgba))
    return xhot, yhot


def write_rgba_png(out_png: Path, width: int, height: int, rgba_bytes: bytes) -> None:
    """Encode raw 8-bit RGBA pixels into a PNG file using Python stdlib only."""
    def png_chunk(tag: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    stride = width * 4
    scanlines = bytearray()
    for y in range(height):
        scanlines.append(0)  # filter type 0 (None)
        scanlines.extend(rgba_bytes[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(scanlines), level=6)
    png_data = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", idat) + png_chunk(b"IEND", b"")
    out_png.write_bytes(png_data)


def create_fallback_cursor_png(out_png: Path, size: int = 24) -> tuple[int, int]:
    """Generate a simple fallback arrow cursor PNG using pure Python."""
    w, h = 16, 22
    rgba = bytearray(w * h * 4)
    # Simple white arrow with black outline
    rows = [
        "X...............",
        "XX..............",
        "XWX.............",
        "XWWX............",
        "XWWWX...........",
        "XWWWWX..........",
        "XWWWWWX.........",
        "XWWWWWWX........",
        "XWWWWWWWX.......",
        "XWWWWWWWWX......",
        "XWWWWWXXXX......",
        "XWWXWWX.........",
        "XWX.XWWX........",
        "XX..XWWX........",
        "X....XWWX.......",
        ".....XWWX.......",
        "......XX........",
    ]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            idx = (y * w + x) * 4
            if ch == "X":
                rgba[idx : idx + 4] = b"\x11\x11\x11\xff"
            elif ch == "W":
                rgba[idx : idx + 4] = b"\xff\xff\xff\xff"
    write_rgba_png(out_png, w, h, bytes(rgba))
    return 0, 0


def cmd_capture(args: argparse.Namespace) -> int:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    session_dir = Path(tempfile.mkdtemp(prefix="nimbush-screenshot-", dir=runtime_dir))

    outputs: list[dict] = []
    if args.outputs:
        output_names = args.outputs
    else:
        # Query Hyprland monitors if available
        output_names = []
        if shutil.which("hyprctl"):
            res = subprocess.run(
                ["hyprctl", "-j", "monitors"],
                capture_output=True,
                text=True,
            )
            if res.returncode == 0:
                try:
                    monitors = json.loads(res.stdout)
                    output_names = [m["name"] for m in monitors if not m.get("disabled", False)]
                except json.JSONDecodeError:
                    output_names = []

    if output_names:
        for name in output_names:
            out_file = session_dir / f"{name}.png"
            out_cursor_file = session_dir / f"{name}_cursor.png"
            res = subprocess.run(["grim", "-o", name, str(out_file)], capture_output=True, text=True)
            if res.returncode != 0 or not out_file.is_file():
                shutil.rmtree(session_dir, ignore_errors=True)
                print(json.dumps({"error": res.stderr.strip() or f"grim failed for {name}"}))
                return 1
            res_c = subprocess.run(["grim", "-c", "-o", name, str(out_cursor_file)], capture_output=True, text=True)
            if res_c.returncode != 0 or not out_cursor_file.is_file():
                shutil.copy2(out_file, out_cursor_file)
            w, h = get_image_size(out_file)
            outputs.append({
                "name": name,
                "path": str(out_file),
                "cursorPath": str(out_cursor_file),
                "width": w,
                "height": h,
            })
    else:
        out_file = session_dir / "full.png"
        out_cursor_file = session_dir / "full_cursor.png"
        res = subprocess.run(["grim", str(out_file)], capture_output=True, text=True)
        if res.returncode != 0 or not out_file.is_file():
            shutil.rmtree(session_dir, ignore_errors=True)
            print(json.dumps({"error": res.stderr.strip() or "grim failed"}))
            return 1
        res_c = subprocess.run(["grim", "-c", str(out_cursor_file)], capture_output=True, text=True)
        if res_c.returncode != 0 or not out_cursor_file.is_file():
            shutil.copy2(out_file, out_cursor_file)
        w, h = get_image_size(out_file)
        outputs.append({
            "name": "full",
            "path": str(out_file),
            "cursorPath": str(out_cursor_file),
            "width": w,
            "height": h,
        })

    print(json.dumps({"sessionDir": str(session_dir), "outputs": outputs}))
    return 0


def cmd_process(args: argparse.Namespace) -> int:
    src = Path(args.source)
    if not src.is_file():
        notify("Screenshot failed", "Source image not found.")
        print(json.dumps({"error": "Source image not found"}))
        return 1

    session_dir = Path(args.session_dir) if args.session_dir else src.parent
    out_file = session_dir / "cropped.png"

    try:
        cursor_png: Path | None = None
        rel_x = 0
        rel_y = 0
        if args.include_pointer and args.pointer_x is not None and args.pointer_y is not None:
            theme, cursor_size = read_cursor_config()
            cursor_png = session_dir / "cursor.png"
            xhot, yhot = 0, 0
            xcursor_path = find_xcursor_file(theme)
            parsed = parse_xcursor_to_png(xcursor_path, cursor_size, cursor_png) if xcursor_path else None
            if parsed is not None:
                xhot, yhot = parsed
            else:
                xhot, yhot = create_fallback_cursor_png(cursor_png, cursor_size)

            rel_x = args.pointer_x - args.x - xhot
            rel_y = args.pointer_y - args.y - yhot

        if shutil.which("magick"):
            proc_cmd = [
                "magick",
                str(src),
                "-crop",
                f"{args.w}x{args.h}+{args.x}+{args.y}",
                "+repage",
            ]
            if cursor_png is not None:
                proc_cmd.extend([str(cursor_png), "-geometry", f"{rel_x:+d}{rel_y:+d}", "-composite"])
            proc_cmd.append(str(out_file))
        elif shutil.which("ffmpeg"):
            if cursor_png is not None:
                proc_cmd = [
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(src),
                    "-i",
                    str(cursor_png),
                    "-filter_complex",
                    f"[0:v]crop={args.w}:{args.h}:{args.x}:{args.y}[bg];[bg][1:v]overlay={rel_x}:{rel_y}",
                    "-frames:v",
                    "1",
                    str(out_file),
                ]
            else:
                proc_cmd = [
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(src),
                    "-vf",
                    f"crop={args.w}:{args.h}:{args.x}:{args.y}",
                    "-frames:v",
                    "1",
                    str(out_file),
                ]
        else:
            notify("Screenshot failed", "Neither magick nor ffmpeg is available.")
            print(json.dumps({"error": "Neither magick nor ffmpeg is available"}))
            return 1

        res = subprocess.run(proc_cmd, capture_output=True, text=True)
        if res.returncode != 0 or not out_file.is_file():
            notify("Screenshot failed", res.stderr.strip() or "Image crop failed.")
            print(json.dumps({"error": res.stderr.strip() or "Image crop failed"}))
            return 1

        if args.action == "copy":
            with open(out_file, "rb") as f:
                cp = subprocess.run(["wl-copy", "--type", "image/png"], stdin=f)
            if cp.returncode != 0:
                notify("Screenshot failed", "Could not copy to clipboard.")
                return 1
            notify("Region Screenshot", "Screenshot copied to clipboard.")

        elif args.action == "swappy":
            with open(out_file, "rb") as f:
                subprocess.run(["wl-copy", "--type", "image/png"], stdin=f)
            notify("Region Screenshot", "Copied to clipboard. Opening Swappy.")
            subprocess.run(["swappy", "-f", str(out_file)])

        elif args.action == "save":
            pictures_dir = os.environ.get("XDG_PICTURES_DIR") or str(Path.home() / "Pictures")
            save_dir = Path(pictures_dir) / "Screenshots"
            save_dir.mkdir(parents=True, exist_ok=True)
            timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            dest = save_dir / f"Screenshot_{timestamp}.png"
            shutil.copy2(out_file, dest)
            with open(dest, "rb") as f:
                subprocess.run(["wl-copy", "--type", "image/png"], stdin=f)
            notify("Region Screenshot", f"Saved to {dest.name} and copied to clipboard.")

        print(json.dumps({"ok": True, "action": args.action}))
        return 0
    finally:
        if session_dir.name.startswith("nimbush-screenshot-"):
            shutil.rmtree(session_dir, ignore_errors=True)


def cmd_cleanup(args: argparse.Namespace) -> int:
    session_dir = Path(args.session_dir)
    if session_dir.name.startswith("nimbush-screenshot-") and session_dir.exists():
        shutil.rmtree(session_dir, ignore_errors=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Nimbush screenshot backend")
    sub = parser.add_subparsers(dest="command", required=True)

    p_cap = sub.add_parser("capture")
    p_cap.add_argument("--outputs", nargs="*", default=[])

    p_proc = sub.add_parser("process")
    p_proc.add_argument("--source", required=True)
    p_proc.add_argument("--session-dir", default="")
    p_proc.add_argument("--x", type=int, required=True)
    p_proc.add_argument("--y", type=int, required=True)
    p_proc.add_argument("--w", type=int, required=True)
    p_proc.add_argument("--h", type=int, required=True)
    p_proc.add_argument("--action", choices=["copy", "swappy", "save"], default="copy")
    p_proc.add_argument("--include-pointer", action="store_true")
    p_proc.add_argument("--pointer-x", type=int, default=None)
    p_proc.add_argument("--pointer-y", type=int, default=None)

    p_clean = sub.add_parser("cleanup")
    p_clean.add_argument("--session-dir", required=True)

    args = parser.parse_args()
    if args.command == "capture":
        return cmd_capture(args)
    if args.command == "process":
        return cmd_process(args)
    if args.command == "cleanup":
        return cmd_cleanup(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
