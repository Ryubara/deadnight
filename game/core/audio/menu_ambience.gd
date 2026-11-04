class_name MenuAmbience
extends RefCounted
## The menu's ambience and music (#926, #979): the drive-in's crickets and the projector's motor
## under a slow pad and a few soft bells, with the wind over an empty lot. It starts with the main
## menu and every screen the menu pushes (Settings, Play together, the lobby) keeps it; it ends
## when a night is loading (`NightScreen`) and comes back with the menu
## (`MainMenu.screen_resume`).
##
## The music is two loops on the **Music** bus (its slider is Settings, Audio, "Music") and the
## rest are on the **Ambience** bus (its slider, "Ambience"), so each can be turned down or off on
## its own. The loops are 76, 113 and 47 seconds, which share no factor, so the three never come
## back together (about 4.7 days) and a person who leaves the menu open hears a new combination
## each time round; every note is in D dorian over the held D and A, so any meeting of them is in
## key (`docs/research/menu-music.md`). The crickets and the projector are the night's own Ogg
## files under quieter trims. The levels are set against the menu's hints by
## `tools/audio/menu_speakers.py`, on a laptop and a phone speaker.

## The five layers: the music's pad and bells, the wind (a small speaker keeps it, it is in the
## mids), a low motor (what a small speaker loses) and sparse crickets (the top, kept under the
## hints because they sing where the hints do).
const BEDS: Array[StringName] = [
	&"bed_menu_pad",
	&"bed_menu_bells",
	&"bed_menu_wind",
	&"bed_menu_projector",
	&"bed_menu_crickets",
]


## Starts the bed, or turns it back up if it is fading out. Quiet in the first second: the bed
## fades in from silence at the service's rate.
static func start() -> void:
	for id in BEDS:
		Audio.start_bed(id)


## Fades the bed out and frees its players. Nothing happens when it is not playing.
static func stop() -> void:
	for id in BEDS:
		Audio.stop_bed(id)


## Whether the bed is playing (not counting a fade out that has begun).
static func is_playing() -> bool:
	for id in BEDS:
		if not Audio.is_bed_running(id):
			return false
	return true
