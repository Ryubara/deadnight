class_name MenuAmbience
extends RefCounted
## The menu's ambience bed (#926): the drive-in's crickets and the projector's motor, very quiet,
## on the Ambience bus (its slider is Settings, Audio, "Ambience"). It starts with the main menu
## and every screen the menu pushes (Settings, Play together, the lobby) keeps it; it ends when a
## night is loading (`NightScreen`) and comes back with the menu (`MainMenu.screen_resume`).
##
## It plays the same two Ogg files as the night's own beds (`bed_crickets`, `bed_projector`) under
## quieter trims, as streams: nothing is decoded to samples, no file is new, and the night's
## warm-up finds both files read already (`docs/research/menu-sfx.md`, "The bed"). The levels are
## set against the menu's hints by `tools/audio/menu_speakers.py`, on a laptop and a phone speaker.

## The two layers: a low motor (what a small speaker loses) and sparse crickets (the top, kept
## under the hints because they sing where the hints do).
const BEDS: Array[StringName] = [&"bed_menu_projector", &"bed_menu_crickets"]


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
