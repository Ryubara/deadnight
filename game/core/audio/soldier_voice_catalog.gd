class_name SoldierVoiceCatalog
extends RefCounted
## The soldier's voice: what each moment of the night is called, how many takes it has and how
## it ranks against the others, added to `SoundCatalog` by `build`.
##
## The files are `game/assets/audio/voice/soldier/<event>_<n>.ogg`, made by
## `tools/audio/elevenlabs_voice.py` from `tools/audio/soldier_voice.json` (ElevenLabs text to
## speech, free tier: see `voice/soldier/LICENSE.md`). Every take is a sound of its own,
## `vox_<event>_<n>`, so `VoiceDirector` (not the service's random pick) chooses which one plays.
## The design is `docs/design/audio.md`.

const FOLDER := "voice/soldier/"
const BUS := &"Voice"
const GROUP := &"soldier_voice"
const PREFIX := "vox_"
## The level of every take, how far a teammate's voice carries and what the local player's own is
## lowered by are `SoundMix` (`sound_mix_default.tres`, "Soldier voice").

## Per moment: `takes` (how many files there are), `priority` (a line may cut the one speaking only
## from `VoiceDirector.INTERRUPT_PRIORITY` up, and then only a lower one), `cooldown` (seconds
## before the same player says this moment again) and `chance` (the share of the times that it
## happens that the soldier says anything, so the commonest moments are not a running commentary).
const EVENTS := {
	&"downed": {"takes": 4, "priority": 100, "cooldown": 0.0, "chance": 1.0},
	&"hurt": {"takes": 8, "priority": 90, "cooldown": 1.6, "chance": 0.85},
	&"boss_arrive": {"takes": 5, "priority": 75, "cooldown": 20.0, "chance": 1.0},
	&"boss_dead": {"takes": 4, "priority": 72, "cooldown": 20.0, "chance": 1.0},
	&"close_call": {"takes": 5, "priority": 70, "cooldown": 14.0, "chance": 1.0},
	&"teammate_down": {"takes": 5, "priority": 68, "cooldown": 8.0, "chance": 1.0},
	&"revived": {"takes": 5, "priority": 66, "cooldown": 5.0, "chance": 1.0},
	&"streak": {"takes": 7, "priority": 60, "cooldown": 20.0, "chance": 1.0},
	&"dry": {"takes": 5, "priority": 55, "cooldown": 8.0, "chance": 0.8},
	&"power_low": {"takes": 4, "priority": 52, "cooldown": 30.0, "chance": 1.0},
	&"round_start": {"takes": 5, "priority": 50, "cooldown": 10.0, "chance": 1.0},
	&"grenade": {"takes": 5, "priority": 48, "cooldown": 6.0, "chance": 0.7},
	&"reload": {"takes": 9, "priority": 45, "cooldown": 6.0, "chance": 0.7},
	&"low_ammo": {"takes": 5, "priority": 44, "cooldown": 25.0, "chance": 1.0},
	&"round_clear": {"takes": 5, "priority": 42, "cooldown": 10.0, "chance": 1.0},
	&"power_on": {"takes": 5, "priority": 40, "cooldown": 20.0, "chance": 1.0},
	&"buy_big": {"takes": 4, "priority": 38, "cooldown": 5.0, "chance": 1.0},
	&"buy_weapon": {"takes": 5, "priority": 36, "cooldown": 5.0, "chance": 1.0},
	&"door": {"takes": 5, "priority": 34, "cooldown": 8.0, "chance": 1.0},
	&"kill": {"takes": 10, "priority": 30, "cooldown": 5.0, "chance": 0.45},
	&"idle": {"takes": 5, "priority": 10, "cooldown": 40.0, "chance": 1.0},
}

static var _lengths := {}


## Adds every take as a sound; `add` is `SoundCatalog._add` (id, path under the audio folder,
## variants, options).
static func build(add: Callable) -> void:
	var mix := SoundCatalog.mix()
	for event: StringName in EVENTS:
		var info: Dictionary = EVENTS[event]
		for n in range(1, int(info["takes"]) + 1):
			(
				add
				. call(
					take_id(event, n),
					"%s%s_%d.ogg" % [FOLDER, event, n],
					1,
					{
						"bus": BUS,
						"group": GROUP,
						"priority": info["priority"],
						"pitch_semitones": 0.0,
						"volume_db": mix.voice_db,
						"max_distance": mix.voice_max_distance,
						"unit_size": mix.voice_unit_size,
						"near_cap_db": 0.0,
					}
				)
			)


static func take_id(event: StringName, n: int) -> StringName:
	return StringName("%s%s_%d" % [PREFIX, event, n])


static func events() -> Array:
	return EVENTS.keys()


static func takes_of(event: StringName) -> int:
	return int(EVENTS.get(event, {}).get("takes", 0))


static func path_of(event: StringName, n: int) -> String:
	return "%s%s%s_%d.ogg" % [SoundCatalog.ROOT, FOLDER, event, n]


## How long a take plays, in seconds (read once from its file).
static func length(event: StringName, n: int) -> float:
	var id := take_id(event, n)
	if not _lengths.has(id):
		var stream := load(path_of(event, n)) as AudioStream
		_lengths[id] = stream.get_length() if stream != null else 0.0
	return _lengths[id]
