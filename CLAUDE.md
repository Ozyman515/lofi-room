# Lofi Room: standing rules for working on this project

## Target devices
The room must run on the **Steam Frame**, PCs (Windows, desktop fallback) and the **Meta Quest 3** (standalone
Android, ARM64, OpenXR). Every new feature has to work on the Quest 3 or degrade gracefully there. Read docs/QUEST.md.

For anything new, check these before shipping:
- No spawning programs (OS.create_process / OS.execute) without a `Plat.can_spawn_programs()` guard. The Quest can't.
- Never write into `res://`. Use `user://`. The in-game updater is PC-only (`Plat.can_self_update()`).
- Don't relaunch the process on the Quest; `_relaunch()` restarts the scene instead.
- Mind fill rate: big see-through layers (smoke, haze, fog sheets), full-screen overlays and bloom are expensive.
  Give them a cheaper variant when `Plat.low_power()` is true.
- File access: songs/videos come from `user://` or the Android shared folders; no Windows-only paths.
- Test the Quest paths on a PC with the environment variable `LOFI_QUEST_SIM=1`.
- Platform checks live in `platform.gd`.

## Project conventions
- Pushing an update (`python3 make_update.py <n>`, commit, `git push origin HEAD:main`) only when the owner says so.
- Run the parse check (load the project in Godot) before pushing anything that touches GDScript.
- `tools/` is git-ignored and never shipped (it holds personal extras such as the cat model).
