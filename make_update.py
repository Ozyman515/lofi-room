#!/usr/bin/env python3
"""Writes update.json (SHA-256 of every updatable file). Run before each release:  python3 make_update.py <version>"""
import hashlib, json, os, sys
SKIP = (".godot/", ".git/", "carts/", "addons/godot-vlc/bin/", "addons/webrtc/lib/", "server/", "tools/")
SKIP_FILES = {"update.json", "make_update.py", ".gitattributes", ".gitignore", "project.godot", "CLAUDE.md"}  # project.godot: the editor rewrites it
ver = int(sys.argv[1])
open("version.txt", "w").write("%d\n" % ver)
files = {}
for d, _, fs in os.walk("."):
    for f in fs:
        p = os.path.relpath(os.path.join(d, f), ".").replace(os.sep, "/")
        if p.startswith(SKIP) or p in SKIP_FILES or f.endswith((".import", ".uid")):
            continue
        b = open(p, "rb").read()
        files[p] = {"sha": hashlib.sha256(b).hexdigest(), "size": len(b)}
json.dump({"version": ver, "files": dict(sorted(files.items()))}, open("update.json", "w"), indent=1)
print(len(files), "files, version", ver)
