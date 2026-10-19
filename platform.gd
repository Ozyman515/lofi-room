extends RefCounted
## Where the room is running. The Meta Quest 3 (standalone Android) is a supported target next to the Steam Frame
## and PCs. On it the room can't start other programs (no emulator host, no ffmpeg, no relaunching itself), can't
## write into its own game files (no in-game updater), and has a much smaller graphics budget than a PC.
## Setting the environment variable LOFI_QUEST_SIM=1 on a PC makes the room behave that way, for testing.


static func is_android() -> bool:
	return OS.has_feature("android") or OS.get_environment("LOFI_QUEST_SIM") == "1"


static func can_spawn_programs() -> bool:
	return not is_android()


static func can_self_update() -> bool:
	return not is_android()


# a smaller graphics budget: fewer see-through smoke sheets, no bloom unless asked for
static func low_power() -> bool:
	return is_android()
