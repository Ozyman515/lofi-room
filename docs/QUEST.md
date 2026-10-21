# Running Lofi Room on the Meta Quest 3

The room targets the Steam Frame, PCs and the Meta Quest 3. The Quest 3 is a standalone Android headset (ARM64,
OpenXR), so a few things work differently there. Status after the Quest 3 pass:

| Feature | Quest 3 |
|---|---|
| The room, lighting, rain, windows, curtains, bed, incense | Works (same code). Bloom is off by default, haze uses fewer layers. |
| Controllers, walking, snap turn, pointing at screens | Works. The default OpenXR action map already binds the Oculus/Meta Touch profile. |
| Music player and the room's songs | Works. Songs are copied to the app's own folder on first run; add more with the file browser. |
| Napping / make the bed | Works. The room restarts inside the app instead of launching a second copy. |
| Weather, traffic sound, GIF screens, poster | Works. |
| VCR | Plays `.ogv` (Theora) only. No VLC add-on and no ffmpeg on the headset. |
| Game consoles (NES, SNES, SGB, Genesis, Neo Geo arcade) | **Not yet.** They run in a separate program loading Windows/Linux x86 libretro cores. See "Emulators" below. The consoles show a short "can't run on this headset yet" message. |
| In-game updater | Off on the headset. The app's files are read-only there, so updates arrive as a new install (new APK). |

## Building the APK (on the PC, in the Godot editor, 4.3 or newer)
1. Editor, Editor Settings, Export, Android: set the Java SDK path and Android SDK path (Android Studio installs both).
2. Project, Install Android Build Template.
3. AssetLib: install **Godot OpenXR Vendors** (the Meta/Khronos loaders). Enable the plugin in Project Settings, Plugins.
4. Project, Export, Add, Android:
   - Gradle Build: on. XR Mode: OpenXR. Architectures: arm64-v8a only.
   - Under the OpenXR Vendors options turn on Meta (Quest) support. The project already uses ASTC textures and the Mobile renderer.
   - Permissions: Read/Write External Storage (so the music player and the poster picker can see the headset's Music, Pictures and Download folders).
   - Resources, "Filters to export non-resource files": `*.gif, music/*, media/*, posters/*`
5. Turn on Developer Mode for the headset (Meta Horizon phone app), connect it by USB, and use One-Click Deploy or
   `adb install -r lofi-room.apk`.

## Graphics budget
- `[settings] glow=true` in `user://lofi_room.cfg` turns the bloom back on if the frame rate holds.
- The incense haze uses 24 puffs and 5 haze sheets on the headset (64 and 16 on a PC).
- The room asks for 90 Hz and medium foveation when it starts on the headset.
- To test the headset code paths on a PC, start the game with the environment variable `LOFI_QUEST_SIM=1`.

## Emulators on the Quest (the open piece of work)
`bin/retro_host.c` is a small program that dlopens a libretro core and talks to the room over a loopback socket.
Android can't run a program from the app's data folder and the cores in `cores/` are x86 Windows/Linux builds, so for
the Quest we need: (1) arm64-v8a builds of fceumm, snes9x2010, mgba, genesis_plus_gx and fbneo made with the Android
NDK, and (2) the host built as an arm64 library that the room starts inside its own process (a GDExtension or an
Android plugin) instead of OS.create_process. The cloud workspace this room is developed in can't download the NDK,
so this needs a build on a machine that can.

## Comics
Comics (.cbz, picture PDFs, fixed-layout .epub, or a folder of them read as one book) and ebooks (text .epub and text PDFs, laid out into pages by the room) live in `user://books` on the headset and in the `books`
folder next to the game on a PC. Reading is pure GDScript (zip + the engine's image decoders), so it works
on the Quest; pages are capped at 1600 px there. .cbr (RAR) files can't be opened anywhere; convert them to .cbz.
When friends are in the room, a book you take off your shelf is streamed to whoever picks it up as JPEGs.

## Voice and shared sound
Voices, the host's music and the host's tape travel as IMA ADPCM at 24 kHz (adpcm.gd), about 190 kb/s per
stream, no codec library needed, so it works the same on the Quest. The microphone needs
`audio/driver/enable_input` (on in project.godot); on the Quest the app also needs the RECORD_AUDIO
permission in the export preset.
