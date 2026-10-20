# Building the Windows exe

The room ships as a Godot *runtime* dropped into the project folder: `lofi-room.exe` is Godot's own
Windows export template (release, x86_64) with the room's icon stamped in, and the rest of the folder is
the project itself (scripts, scenes, textures, the `.godot/imported` files). Godot runs a loose project
when it finds `project.godot` next to the exe, so no .pck is involved and the in-game updater keeps
working exactly as it does for the editor copy: it replaces the loose files.

Steps (done on the build machine, not needed by players):

1. Get the template for the Godot version the project is on (the editor's version, see README):
   `python3 pack/fetch_template.py https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz templates/windows_release_x86_64.exe`
   (it reads just that one file out of the 1.2 GB archive).
2. Stamp the icon: `python3 pack/stamp_icon.py windows_release_x86_64.exe icon.png lofi-room.exe`
3. Import the project once with the same Godot version, headless, so `.godot/imported` exists:
   `godot --headless --path . --import`
4. Zip the project folder (minus `.git`, `server`, `pack`, `tools` extras, the Linux/macOS VLC binaries)
   with `lofi-room.exe` in it. Players unzip and double-click the exe; the editor route still works too.

`.godot/imported`, `.godot/extension_list.cfg` and the two other small `.godot` files are committed and
go out through the updater, because the exe build needs them and the editor regenerates identical ones.
A new icon or a project-settings change still needs a fresh zip (the updater never touches `project.godot`).

# Signed updates

Every release is signed with a private key only the owner holds; the room ships the public half
(`update_key.pub`) and refuses any `update.json` that doesn't verify against it, so a hijacked GitHub
account can't push code to players.

- Make the key once: `godot --headless -s pack/keygen.gd -- /safe/place/update_key.pem` (writes
  `update_key.pub` into the project; commit that, back up the .pem, never commit it).
- Release: `GODOT=godot LOFI_UPDATE_KEY=/safe/place/update_key.pem python3 make_update.py <n>` signs as it
  goes, or run `godot --headless -s pack/sign_update.gd -- /safe/place/update_key.pem` after it.
- Lost key: make a new pair and ship a fresh zip; copies with the old public key will stop updating.
