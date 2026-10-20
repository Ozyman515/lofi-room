# Lofi Room (Godot 4.3+, OpenXR: Steam Frame, PCs and Meta Quest 3)

## Just play it (Windows)
Unzip and double-click `lofi-room.exe`. That exe is Godot's own runtime with the room's icon; it runs the
project files next to it, and the in-game updater keeps them current. With SteamVR running and set as the
OpenXR runtime it starts in VR; without a headset it starts as a flat desktop view.

## Run it from the editor (for tinkering)
1. Open Godot, click Import, pick this folder's project.godot.
2. On the PC, start SteamVR and connect your Frame the normal way. Make sure SteamVR is the active OpenXR runtime
   (SteamVR settings, Developer, "Set SteamVR as OpenXR runtime").
3. Press F5 in Godot. The room should appear in the headset.

Controls: left stick = walk, right stick = snap turn. You can also just walk around physically.
No headset connected? It falls back to a flat view: click to look, WASD to move, Esc frees the mouse.

## Meta Quest 3
The room also targets the Quest 3 (standalone Android). What works there, how to build the APK and what is still missing
(the game consoles) is in docs/QUEST.md.

## Tweaking
Everything is in main.gd. Colors are at the top of each _build_* function. USE_GLOW turns the bloom on/off.
The skyline and monitor are shaders in /shaders (colors are uniforms you can edit in the Inspector).

## Running natively on the Frame
Once the PC version works, follow Valve's Godot guide for Steam Frame (Developer Mode, export preset,
Remote Deploy via the SteamOS Devkit Client).

## Poster
The wall poster uses textures/poster.png. Replace that file with your own art (about 1080x1840, portrait) to change it.

## Sitting
Walk up to the desk chair or the beanbag and press A (or the trigger) in VR, or E on the desktop, to sit. Press again to stand.
While seated the chair swivels to follow where you look, so you can turn and look out the window.

## Using your own 3D models
Put bed.glb in the assets folder. It is auto-scaled to the bed's footprint. If it faces the wrong way, change BED_EXTRA_YAW in main.gd (90, 180, 270).

## The CRT corner
The beanbag faces the CRT TV on the left wall. Sit on it the same way as the chair.

## Sizes
TV_WIDTH and RUG_WIDTH at the top of main.gd set the CRT width and lounge rug width (TV is 80% of the rug).

## Changing what's on the TV and the PC monitor
Put your own file in the project's `media` folder (use File Explorer; Godot's FileSystem dock may not list GIFs):
- `media/tv.gif` is the CRT screen (4:3 looks best, e.g. 320x240)
- `media/monitor.gif` is the PC monitor (16:9 looks best, e.g. 480x270)
`.png`, `.jpg` and `.webp` also work as still images. The picture is cropped to fill the screen.
Delete a file and that screen goes back to its built-in look (blue "CH 3" TV, animated bars on the monitor).
The two included GIFs are samples: tv.gif is the blue CH 3 screen, monitor.gif is a moving pink/purple loop.

Tips: GIFs decode on a background thread when the room starts, so big ones take a few seconds to begin moving
(the first frame shows right away). Keep them around 480 px wide or less and under about 100 frames.
If you export the project to the headset, add `*.gif` to Export, Resources, "Filters to export non-resource files".

## Layout
FRONT_Z moves the front (door) wall and LOUNGE_DZ shifts the rug/TV/beanbag set toward it.

## Window
WIN_X0 / WIN_X1 / WIN_Y0 / WIN_Y1 at the top of main.gd set the window's left edge, right edge, sill height and top.
The sill is a thin ledge pressed against the wall, and the window ends right where the monitor starts, so nothing clips the desk.

## Pointing at things (PC and VCR)
- VR: point a controller at the monitor, the TV or the VCR (a laser appears). Trigger = click.
  Right thumbstick up/down scrolls lists. A/B or the trigger (when not pointing at a screen) still sits/stands.
- Desktop: click to capture the mouse, aim the crosshair, left-click. Mouse wheel scrolls. E sits/stands, Esc frees the mouse.

## Music (the PC)
Point at the monitor and click "Music" in the taskbar. Browse your folders (Music, Downloads, Drives...) and click a song.
Plays mp3, ogg and 16-bit wav. It queues the other songs in the same folder, with prev / play-pause / next / stop, a seek bar and volume.
Sound comes from the desk and fades as you walk away.

## Video (the VCR on the TV)
Point at the VCR's EJECT button (or its tape slot) and click, then pick any video file on your PC.
- **VLC is built in** (the godot-vlc add-on in `addons/godot-vlc`, Windows and Linux x64). mkv, mp4, avi, mov, webm... all play
  straight away, no converting. It uses VLC's own decoders, so it handles nearly anything VLC does.
- VCR buttons, left to right: REWIND (10 s), FAST FORWARD (30 s), PLAY/PAUSE, STOP, EJECT (pick another video), AUDIO/SUBS.
- STOP and PAUSE both keep your place: press PLAY and it carries on from there.
- **Q** (or the purple PICTURE button at the right end of the VCR's button row, which works in VR too) cycles the picture shape: original, zoom (crops the picture to fill the whole screen), stretch, and 16:9. The choice is kept for the next video.
- AUDIO/SUBS opens VLC's track lists: pick an audio language and a subtitle track (or Off). It changes instantly and the
  picture keeps playing when you close the panel. Text and picture (DVD/Blu-ray) subtitles both work.
- TV buttons (right side of the TV): POWER, VOL -, VOL +. Switching the TV off pauses the tape exactly where it is,
  and switching it back on carries on. The little cursor on the TV hides while a video is playing.
- Subtitle/audio names come from the file's own tags (for example "Track 1 - [Japanese]").
- If the add-on can't load (for example a native Steam Frame build, which is ARM, or macOS) the VCR falls back to the old way:
  .ogv plays directly and other formats are converted with ffmpeg (the bundled tools/ffmpeg.exe, or one on your PATH), cached for next time, with
  no seeking. The AUDIO/SUBS button still works in that mode for text subtitles and audio languages.
Your last folders are remembered in user://lofi_room.cfg.

### TrueHD audio
LibVLC's TrueHD decoder comes out garbled (mostly silence) inside Godot. If ffmpeg is found, the first time you load a file
with a TrueHD track the room copies it with only that audio swapped to FLAC ("PREPARING TAPE", video is not re-encoded, so it is
much quicker than a conversion) and caches the result in `user://vcr_cache`. Without ffmpeg the file plays as is, with bad TrueHD sound.

### About the VLC add-on
- Files: `addons/godot-vlc/` (about 440 MB with LibVLC inside) and `.godot/extension_list.cfg` (tells Godot to load it on the very first run).
- License: LGPL (LibVLC). The add-on's LICENSE file is in its folder.
- Godot prints lots of "stale plugins cache" lines from libvlc in the console on the first run. They are harmless.
- When you share the project, send the whole folder (the add-on is part of it). If a friend opens it on macOS the VCR uses the fallback above.

## Close-up views (V on desktop, B or Y in VR)
Press V (desktop) or B/Y (VR) to cycle: normal -> zoomed in -> screen fills the view -> back to where you were.
It targets the screen you're pointing at, or the one you're looking toward. In VR it moves you in front of the screen
(it never comes closer than 45 cm, which is about as close as eyes can focus). Walking away ends the close-up.
A/X and the trigger (when not pointing at a screen) still sit and stand.

## Weather, curtains and the monitor button
- **Weather:** on the PC click **Weather** in the taskbar and pick Clear, Rain, Snow or Storm. It changes the sky and haze, adds falling
  rain or snow outside the window, and plays rain/wind sounds (all generated in code, no audio files). The Storm adds lightning flashes
  and thunder. Each weather has its own intensity slider in the same window (rain: drizzle to downpour, snow: flurries to whiteout, storm: light to heavy, where heavier storms flash more often and the thunder arrives sooner and louder). Thunder is as loud as the rain at 50 % storm intensity and drowns it out above that, lightning bolts streak down outside the window, and from about 80 % each strike lights up the whole room and city for a few seconds. There is also an ambient volume slider (it controls the weather and the traffic).
  **City traffic:** with clear or light weather you hear a low city rumble, cars passing by (left to right and back), now and then a honk (2 to 4 beeps, each short or long, 2 to 4 seconds in all) and every so often a police or ambulance siren (under 5 seconds) that swells and fades as it passes from one side to the other. It fades out as the active weather's intensity goes from 30 % to 60 % and is silent from 60 % up. The curtains muffle it like the weather. Every time the game starts, a random weather (clear, rain, snow or storm) and a random intensity are picked. The Weather window also has a button that mutes only the traffic. On clear nights and in light weather a few faint stars show in the sky.

  **An easter egg** is hidden in the room (hint: the old TV has something scratched into its side, and the right cart is hidden). It needs the right cart in the console. It is not saved or unlocked; you can trigger it whenever you like, and it takes about 30 seconds.
- **Blackout curtains:** click either wall switch beside the window (left or right) or the button in the PC's Weather window. The curtain rolls
  down from the top in about 3 seconds, and the room goes dark apart from the lamps, fairy lights, TV, monitor, speaker LEDs and the ceiling strip.
  The **slider** in the Weather window closes the curtain part-way (and follows the curtain while it moves). The wall switches and the PC button work like a remote: press to start lowering or raising, press again while it moves to stop it anywhere, then press again to send it back the other way.
  Less window means a darker room, and the weather sound is only muffled a little when half closed, so you can keep rain or thunder audible while watching the TV. Fully down, it is muffled a lot.
- **Lights:** click a lamp (nightstand, desk, paper lantern) to switch it off, or use **Lights** in the PC taskbar: ALL ON / ALL OFF plus the nightstand lamp, desk lamp, paper lantern, fairy lights and the ceiling strip. The TV and monitor have their own power buttons.
- **Game console and carts:** slide the POWER switch on the console by the TV (or click it). The TV switches to the console picture and the LED lights green; slide it back and the TV returns to the VCR (a playing tape pauses while the console is on). The console takes game carts: point at a cart and click to put it in (the cart already inside is taken out), click the cart in the slot to take it out again. Three carts are in the room: a NES cart on the rug beside the console, a SNES cart on top of the TV, and a plain unlabeled one that is hidden somewhere (hint: furniture with a drawer).
  - **NES and SNES carts** play real games. Put your own game files in `carts/nes/roms` (`.nes`) and `carts/snes/roms` (`.sfc` / `.smc`, not zipped); the folders are created on the first run, and battery saves go to the `saves` folder next to them. The TV shows a game list. Pick up a controller from the rug (point at it and click; in VR it appears in your hand), then use the d-pad / stick and A or START to choose. While you hold a controller you cannot walk, and pointing is off. **Put it down** with the grip button (VR) or E (desktop), or the right stick click on a gamepad. To leave a game and go back to the game list, hold START + SELECT for a second, or press M on the desktop (the cart stays in).
  - **SGB and Genesis carts** work the same way: `carts/sgb/roms` takes Game Boy, Game Boy Color and Game Boy Advance files, `carts/gen/roms` takes Sega Genesis / Mega Drive files (`.md`, `.gen`, `.smd`) plus Master System (`.sms`) and Game Gear (`.gg`).
  - **Neo Geo arcade cabinet** (Metal Slug and the rest): a standing cabinet on the left wall. Put the Neo Geo game zips (for example `mslug3.zip`) **and the BIOS `neogeo.zip`** in `carts/neo/roms`, put the Neo Geo cart in the cabinet's cart bay, then click the stick and buttons to play. SELECT is the coin, START starts.
  - **Channel knob on the TV** flips the picture between CLEAN (flat, no scanlines), OLD TV and STRONG CRT; the choice is remembered.
  - **Remapping:** while you hold a controller and the TV shows the game list (or NO CART), press SELECT (Backspace / Tab on the keyboard, BACK on a gamepad, left stick click in VR) to open **Controls**. Pick a button, press A, then press the button you want for it. It works for the gamepad, the keyboard and the VR controllers separately (DEVICE row), and listens for the actual button you press, so any pad works. The LAYOUT row (gamepad) switches between *console positions* (bottom button = B, like the real console) and *Xbox labels* (A is A). Choosing a button already used by another swaps the two. RESET THIS DEVICE restores the defaults. The menus always answer to the d-pad / stick, the face buttons and START, so a bad binding can never lock you out. Your choices are saved.
  - **VR controls:** left stick = d-pad, right A = A, right B = B, left X = Y, left Y = X, triggers = R / L, left menu button or right stick click = START, left stick click = SELECT.
  - **Changing controls from the PC:** click **Settings** on the PC, then **Controls...** at the top. Pick the device (keyboard, gamepad), click a button and press the key or button you want. It changes the TV consoles and the arcade together, and is saved.
  - **Desktop controls:** arrow keys = d-pad, X = A, Z = B, A = Y, S = X, Q = L, W = R, Enter = START, Backspace = SELECT. A connected gamepad works as well.
  - The game runs on its own clock at full speed, even when the room itself runs at a low frame rate. On the desktop the held controller moves down as you zoom in on the TV (V key) so it stays out of the picture.
  - The game's sound comes out of the TV and follows its volume and power. Windows only for now. If a game does not start, `carts/emulator.log` says why. The games are your own files; none are included.
  - **The plain cart** plays a built-in run-and-gun demo, and is the only one the easter egg works with.
- **Settings (PC taskbar):** **Aiming dot** turns the small dot in the middle of the view on or off (desktop view only; in VR the laser does that) and lets you pick its colour: Pink, Cyan, Amber, Lavender or White. The dot grows a thin ring when you point at something you can click. Your choice is remembered.
- **Monitor:** the small button at the bottom right of the monitor's frame switches the screen off and on. The music keeps playing.

## ffmpeg for the VCR
`tools/ffmpeg.exe` (Windows, GPL build from BtbN/FFmpeg-Builds, https://github.com/BtbN/FFmpeg-Builds) ships with the project, so TrueHD fixing and conversions work out of the box. Linux/Mac: install ffmpeg and restart Godot. FFmpeg's license is GPL; its source is available at ffmpeg.org.

## Sending the project to someone
Open it once in the Godot editor so it imports the images and shaders, then press F5. (Scripts no longer depend on
Godot's class cache, so a fresh copy runs without the "could not find type" errors.)

_Update test: version 35 installed through the in-game updater._

## Resume where you left off
Games keep your place automatically: when you leave a game, switch the console or cart, or close the room, the exact position is saved and comes back next time you start that game (Settings > "Games keep your place" turns this off). Battery saves still work as usual.
