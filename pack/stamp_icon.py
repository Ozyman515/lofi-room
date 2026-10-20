#!/usr/bin/env python3
"""Puts the room's icon into a Godot Windows export template (release, x86_64) without rcedit.

The template already carries Godot's own icon as six resources (16, 32, 48, 64, 128 px bitmaps and a
256 px PNG). Same-size bitmaps are written over the old ones in place, the PNG is written as a
256-colour PNG that fits in the old one's slot, and the resource sizes are updated. Nothing moves, so
the file stays valid.

    python3 stamp_icon.py windows_release_x86_64.exe icon.png lofi-room.exe
"""
import io, struct, sys
from PIL import Image

RT_ICON, RT_GROUP_ICON = 3, 14


def parse_resources(d):
    pe = struct.unpack("<I", d[0x3c:0x40])[0]
    nsec = struct.unpack("<H", d[pe + 6:pe + 8])[0]
    opt = struct.unpack("<H", d[pe + 20:pe + 22])[0]
    st = pe + 24 + opt
    rsrc = None
    for i in range(nsec):
        s = d[st + i * 40:st + i * 40 + 40]
        if s[:8].rstrip(b"\0") == b".rsrc":
            vs, va, rs, ro = struct.unpack("<IIII", s[8:24])
            rsrc = (va, ro)
    if rsrc is None:
        raise SystemExit("no .rsrc section")
    base_va, base_raw = rsrc

    def read_dir(off):
        n_named, n_id = struct.unpack("<HH", d[off + 12:off + 16])
        return [struct.unpack("<II", d[off + 16 + i * 8:off + 24 + i * 8]) for i in range(n_named + n_id)]

    res = {}
    for t, sub in read_dir(base_raw):
        if t & 0x80000000:
            continue
        for name, sub2 in read_dir(base_raw + (sub & 0x7fffffff)):
            for lang, leaf in read_dir(base_raw + (sub2 & 0x7fffffff)):
                entry = base_raw + leaf
                rva, size = struct.unpack("<II", d[entry:entry + 8])
                res.setdefault(t, []).append({"name": name, "off": rva - base_va + base_raw, "size": size, "entry": entry})
    return res


def dib_icon(im, size):
    """A 32-bit BMP icon image: BITMAPINFOHEADER (height doubled), bottom-up BGRA pixels, then the AND mask."""
    im = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    hdr = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    px = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            r, g, b, a = im.getpixel((x, y))
            px += bytes((b, g, r, a))
    row = ((size + 31) // 32) * 4
    mask = bytearray()
    for y in range(size - 1, -1, -1):
        bits = bytearray(row)
        for x in range(size):
            if im.getpixel((x, y))[3] < 128:
                bits[x // 8] |= 0x80 >> (x % 8)
        mask += bits
    return bytes(hdr) + bytes(px) + bytes(mask)


def png_icon(im, limit):
    im = im.resize((256, 256), Image.LANCZOS).convert("RGBA")
    for colors in (256, 128, 64, 32, 16):
        q = im.quantize(colors=colors, method=Image.Quantize.FASTOCTREE)
        b = io.BytesIO()
        q.save(b, "PNG", optimize=True)
        if len(b.getvalue()) <= limit:
            return b.getvalue()
    raise SystemExit("the 256 px icon does not fit in the template's slot even at 16 colours")


def main(template, icon, out):
    d = bytearray(open(template, "rb").read())
    im = Image.open(icon).convert("RGBA")
    res = parse_resources(d)
    icons = {e["name"]: e for e in res.get(RT_ICON, [])}
    groups = res.get(RT_GROUP_ICON, [])
    if not icons or not groups:
        raise SystemExit("the template has no icon to replace")
    g = groups[0]
    goff = g["off"]
    count = struct.unpack("<H", d[goff + 4:goff + 6])[0]
    for i in range(count):
        e = goff + 6 + i * 14
        w, h, colors, reserved, planes, bpp, size, ident = struct.unpack("<BBBBHHIH", d[e:e + 14])
        ent = icons[ident]
        old = d[ent["off"]:ent["off"] + ent["size"]]
        if old[:8] == b"\x89PNG\r\n\x1a\n":
            blob = png_icon(im, ent["size"])
        else:
            dim = w if w else 256
            blob = dib_icon(im, dim)
            if len(blob) != ent["size"]:
                raise SystemExit("unexpected bitmap size for %d px: %d vs %d" % (dim, len(blob), ent["size"]))
        d[ent["off"]:ent["off"] + len(blob)] = blob
        if len(blob) < ent["size"]:
            d[ent["off"] + len(blob):ent["off"] + ent["size"]] = bytes(ent["size"] - len(blob))
        struct.pack_into("<I", d, ent["entry"] + 4, len(blob))        # resource data size
        struct.pack_into("<I", d, e + 8, len(blob))                   # dwBytesInRes in the group
        print("icon %3d px: %6d bytes" % (w if w else 256, len(blob)))
    # the optional-header checksum is not checked for plain exes; zero it so it is not wrong
    pe = struct.unpack("<I", d[0x3c:0x40])[0]
    struct.pack_into("<I", d, pe + 24 + 64, 0)
    open(out, "wb").write(d)
    print("wrote", out)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
