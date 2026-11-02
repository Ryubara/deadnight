class_name SoundMix
extends Resource
## The mix numbers that belong to no single sound: how many voices each group may hold, and the
## soldier's voice. The shipped values are in `sound_mix_default.tres`; `SoundCatalog.mix()` is how
## the game and the tests read it. (One sound's own level is its `SoundDef`, in a bank under
## `banks/`.)

const SHIPPED_PATH := "res://core/audio/sound_mix_default.tres"

@export_group("Voice budget")
## How many voices a group may hold at once. Past it a louder or higher-priority sound takes the
## weakest voice; anything else is dropped. A sound's group is its `SoundDef.group`.
@export var group_limits: Dictionary[StringName, int] = {
	&"ui": 4,
	&"ui_hint": 1,
	&"challenge": 1,
	&"gun": 12,
	&"reload": 4,
	&"step": 8,
	&"step_own": 2,
	&"zombie_voice": 6,
	&"zombie_boss": 2,
	&"zombie_step": 5,
	&"generator": 2,
	&"grenade": 8,
	&"sting": 1,
	&"board": 4,
	&"door": 2,
	&"melee": 4,
	&"till": 2,
	&"soldier_voice": 3,
	&"bed": 4,
	&"gun_tail": 4,
	&"impact": 6,
	&"swap": 2,
	&"breaker": 2,
	&"shop": 4,
	&"points": 2,
}

@export_group("Soldier voice")
## The level of every take of the soldier's voice on the Voice bus, in dB. Measured against the
## guns and the beds in a night capture (`docs/research/audio.md`).
@export_range(-40.0, 12.0, 0.1, "suffix:dB") var voice_db: float = -4.0
## What the local player's own voice (flat, in their head) is lowered by on top of `voice_db`, in
## dB.
@export_range(-24.0, 0.0, 0.1, "suffix:dB") var own_voice_db: float = -2.0
## A teammate's voice carries this far (metres) ...
@export_range(1.0, 200.0, 0.5, "suffix:m") var voice_max_distance: float = 40.0
## ... and halves at this distance.
@export_range(0.5, 50.0, 0.5, "suffix:m") var voice_unit_size: float = 6.0
