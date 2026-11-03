class_name SmallMapSoundTuning
extends Resource
## How the second map's sound follows the listener, as opposed to how loud each sound is (a sound's
## own level, pitch and reach are its `SoundDef` in `core/audio/banks/smallmap.tres`): the room
## tone's level in each room, what a wall, a boarded window and an open one do to the yard heard
## through them, and how often a fence rattles. The shipped values are in
## `smallmap_sound_tuning_default.tres`: edit that file in the inspector;
## `SmallMapSoundTuning.current()` is how the game and the tests read it.

const SHIPPED_PATH := "res://gameplay/night/smallmap_sound_tuning_default.tres"
## What a level of this or less means: silence (a bed's own floor).
const SILENT_DB := -60.0

static var _shipped: SmallMapSoundTuning = null

@export_group("Rooms")
## The room tone's level in each room (the rooms' node names in the greybox), in dB under its own
## level. A room not listed, and the outside, have none.
@export var tone_db: Dictionary[StringName, float] = {
	&"Start": 0.0, &"Side": 0.0, &"UpperA": -2.0, &"UpperB": -2.0
}
## The wind under the roof, the same way: heard upstairs only.
@export var roof_db: Dictionary[StringName, float] = {&"UpperA": -4.0, &"UpperB": 0.0}

@export_group("The yard")
## What a yard sound loses getting through a wall, on top of the distance.
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var wall_db := -15.0
## ... through a window that still has boards on it ...
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var boarded_db := -8.0
## ... and through one with none (or a breach).
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var open_db := -1.5
## The low-pass of each way in (a player's attenuation filter; the web build plays samples, which
## ignore it, so it also takes `no_filter_db` off).
@export_range(200.0, 20000.0, 50.0, "suffix:Hz") var wall_cutoff_hz := 900.0
@export_range(200.0, 20000.0, 50.0, "suffix:Hz") var boarded_cutoff_hz := 2200.0
@export_range(200.0, 20000.0, 50.0, "suffix:Hz") var open_cutoff_hz := 6000.0
@export_range(-12.0, 0.0, 0.5, "suffix:dB") var no_filter_db := -3.0
## A yard loop's level moves at most this fast (so stepping past a window is a fade, not a cut).
@export_range(1.0, 120.0, 1.0, "suffix:dB/s") var slew_db_per_s := 30.0
## How often the listener's rooms and ways in are looked at.
@export_range(1.0, 60.0, 1.0, "suffix:Hz") var update_hz := 10.0
## How far in from a window's middle the way in is probed from (clear of the players-only blocker).
@export_range(0.2, 2.0, 0.05, "suffix:m") var window_inset := 0.5

@export_group("Rattle")
## A fence rattles somewhere in the yard every so many seconds, between these.
@export_range(1.0, 120.0, 0.5, "suffix:s") var rattle_gap_min := 12.0
@export_range(1.0, 120.0, 0.5, "suffix:s") var rattle_gap_max := 25.0
## Only a post this near the listener rattles.
@export_range(5.0, 200.0, 1.0, "suffix:m") var rattle_reach := 60.0

@export_group("Windows")
## Where a window's boards sound: this far over the window's foot (the middle of its opening).
@export_range(0.0, 3.0, 0.05, "suffix:m") var window_lift := 1.55
## The boards a window starts with, until the server says (`board_torn` carries what is left).
@export_range(1, 12, 1) var boards_full := 6


static func current() -> SmallMapSoundTuning:
	if _shipped == null:
		_shipped = load(SHIPPED_PATH) as SmallMapSoundTuning
	return _shipped
