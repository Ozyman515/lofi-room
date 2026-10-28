#!/usr/bin/env python3
"""Writes update.json (SHA-256 of every updatable file). Run before each release:  python3 make_update.py <version>"""
import hashlib, json, os, sys
SKIP = (".godot/editor/", ".godot/shader_cache/", ".godot/exported/", ".git/", "carts/", "addons/godot-vlc/bin/", "addons/webrtc/lib/", "server/", "tools/", "books/", "pack/",
        "cores/dolphin-emu/Sys/", "cores/dolphin-emu/Sys.unpacking/", "cores/dolphin-emu/Sys.old/")   # (Dolphin's data: unpacked on each PC from Sys.zip)
SKIP_FILES = {"update.json", "update.json.sig", "update_key.pub", "make_update.py", ".gitattributes", ".gitignore", "project.godot", "CLAUDE.md"}  # project.godot: the editor rewrites it; the key only changes with a fresh install
ver = int(sys.argv[1])
open("version.txt", "w").write("%d\n" % ver)
files = {}
for d, _, fs in os.walk("."):
    for f in fs:
        p = os.path.relpath(os.path.join(d, f), ".").replace(os.sep, "/")
        if p.startswith(SKIP) or p in SKIP_FILES or f.endswith(".uid"):
            continue
        b = open(p, "rb").read()
        files[p] = {"sha": hashlib.sha256(b).hexdigest(), "size": len(b)}
# only files that are actually pushed: anything git ignores would 404 on the updater's download
import subprocess
ign = subprocess.run(["git", "check-ignore", "--stdin"], input="\n".join(files), capture_output=True, text=True).stdout.split()
for p in ign:
    files.pop(p, None)
# files that older copies still have and should lose (the updater deletes them if present)
REMOVE = ["music/zephiramusic-tokyo-lofi.mp3", "noir/konstantinpazuzustudio-gritty-noir.ogg", "textures/poster.png", "textures/poster.png.import"]
json.dump({"version": ver, "files": dict(sorted(files.items())), "remove": REMOVE}, open("update.json", "w"), indent=1)
print(len(files), "files, version", ver)
# the release must be signed or no copy of the room will install it:  godot --headless -s pack/sign_update.gd -- <private key>
import subprocess
godot = os.environ.get("GODOT")
key = os.environ.get("LOFI_UPDATE_KEY")
if godot and key:
    r = subprocess.run([godot, "--headless", "--path", ".", "-s", "pack/sign_update.gd", "--", key], capture_output=True, text=True)
    print([l for l in (r.stdout + r.stderr).splitlines() if "sign" in l.lower()][-1:] or r.returncode)
    if r.returncode != 0 or not os.path.exists("update.json.sig"):
        raise SystemExit("signing failed")
else:
    if os.path.exists("update.json.sig"):
        os.remove("update.json.sig")
    print("NOT SIGNED: set GODOT and LOFI_UPDATE_KEY (or run pack/sign_update.gd) before pushing, or nobody will get this update")
