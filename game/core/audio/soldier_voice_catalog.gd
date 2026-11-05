class_name SoldierVoiceCatalog
extends RefCounted
## The soldiers' voices: what each moment of the night is called, how many takes it has and how
## it ranks against the others, added to `SoundCatalog` by `build`.
##
## Two voices say the same moments with the same number of takes each: the male one
## (`game/assets/audio/voice/soldier/<event>_<n>.ogg`, from `tools/audio/soldier_voice.json`) and
## the female one (`voice/soldier_female/`, from `soldier_voice_female.json`), both made by
## `tools/audio/elevenlabs_voice.py` (ElevenLabs text to speech, free tier: see each folder's
## `LICENSE.md`). Every take is a sound of its own, `vox_<event>_<n>` (male) or
## `voxf_<event>_<n>` (female), so `VoiceDirector` (not the service's random pick) chooses which
## one plays. The design is `docs/design/audio.md`.

const MALE := &"male"
const FEMALE := &"female"
const BUS := &"Voice"
const GROUP := &"soldier_voice"
## Per voice: where its files are (under the audio folder) and what its sound ids start with.
const VOICES := {
	MALE: {"folder": "voice/soldier/", "prefix": "vox_"},
	FEMALE: {"folder": "voice/soldier_female/", "prefix": "voxf_"},
}
## The progression moments (#1063): the cheers for a level, a tier, an unlock, a challenge done, a
## poster set, a card, an emblem or frame and the first game of the day. Each ranks above the
## chatter (kills, reloads, idle) and below the urgent lines (hurt, downed, a boss, a teammate
## down), so an urgent line cuts one and one never cuts an urgent line.
const PROGRESS: Array[StringName] = [
	&"level_up",
	&"tier_up",
	&"unlock",
	&"challenge_done",
	&"poster_set",
	&"card",
	&"emblem",
	&"first_game",
]
## The progression events a game server tells every client (`XpAward`), and the moment each one
## becomes. An `unlock_earned` is a card, an emblem (or a frame) or a plain unlock by its slot.
## A `challenge_done` (the challenge tracker, #1076) is its own cheer, and so is a `poster_set_done`
## (the tracker's, #1073).
const CHEER_OF_EVENT: Dictionary[StringName, StringName] = {
	&"level_up": &"level_up",
	&"tier_up": &"tier_up",
	&"challenge_done": &"challenge_done",
	&"poster_set_done": &"poster_set",
}
const CHEER_OF_SLOT: Dictionary[StringName, StringName] = {
	&"calling_cards": &"card",
	&"tier_card": &"card",
	&"emblem": &"emblem",
	&"tier_emblem": &"emblem",
	&"plate_frame": &"emblem",
}
## Which cheer a player gets when several of their events arrive together: the highest weight (a
## tier over a challenge or what a level unlocks over the level), the first of equals. A level that
## gives an item is cheered for the item; a challenge is something the player did, a level is what
## doing it paid, so a challenge that pays a level is cheered as the challenge. The same goes for
## the set a challenge finishes (it arrives with that challenge, and with the tier its XP may
## cross): a set is the rarest thing a player does, so it is said over a tier and over the
## challenge that finished it.
const CHEER_WEIGHT: Dictionary[StringName, int] = {
	&"poster_set": 4,
	&"tier_up": 3,
	&"challenge_done": 2,
	&"unlock": 2,
	&"card": 2,
	&"emblem": 2,
	&"level_up": 1,
}
const FOLDER := "voice/soldier/"
const PREFIX := "vox_"
## The level of every take, how far a teammate's voice carries and what the local player's own is
## lowered by are `SoundMix` (`sound_mix_default.tres`, "Soldier voice").

## Per moment: `takes` (how many files there are), `priority` (a line may cut the one speaking only
## from `NightSoundTuning.interrupt_priority` up, and then only a lower one), `cooldown` (seconds
## before the same player says this moment again) and `chance` (the share of the times that it
## happens that the soldier says anything, so the commonest moments are not a running commentary).
static var _lengths := {}


## The moments, `{event: {takes, priority, cooldown, chance}}`: the resource `SoldierMoments`
## (`soldier_moments_default.tres`, in the inspector).
static func moments() -> Dictionary:
	return SoldierMoments.table()


## Adds every take of every voice as a sound; `add` is `SoundCatalog._add` (id, path under the
## audio folder, variants, options).
static func build(add: Callable) -> void:
	var mix := SoundCatalog.mix()
	for voice: StringName in VOICES:
		for event: StringName in moments():
			var info: Dictionary = moments()[event]
			for n in range(1, int(info["takes"]) + 1):
				(
					add
					. call(
						take_id(event, n, voice),
						"%s%s_%d.ogg" % [VOICES[voice]["folder"], event, n],
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
							"deferred": true,
						}
					)
				)


static func voices() -> Array:
	return VOICES.keys()


## The voice a player speaks with: the `voice` of their frame entry (`female` or `male`), the male
## one when it names none or an unknown one.
static func voice_of(player: Dictionary) -> StringName:
	var voice := StringName(player.get("voice", MALE))
	return voice if VOICES.has(voice) else MALE


static func take_id(event: StringName, n: int, voice := MALE) -> StringName:
	return StringName("%s%s_%d" % [VOICES[voice]["prefix"], event, n])


## Whether `id` is one of the voices' takes (they are built from the moments table and the mix, not
## from rows of the sound table).
static func is_take(id: StringName) -> bool:
	var text := String(id)
	for voice: StringName in VOICES:
		if text.begins_with(VOICES[voice]["prefix"]):
			return true
	return false


## Whether `event` is one of the progression moments.
static func is_progress(event: StringName) -> bool:
	return PROGRESS.has(event)


## The cheer a server event of the night is, or `&""` when it is none (`CHEER_OF_EVENT`,
## `CHEER_OF_SLOT`).
static func cheer_of(event: Dictionary) -> StringName:
	var type: StringName = event["type"]
	if type == &"unlock_earned":
		return CHEER_OF_SLOT.get(StringName(event.get("slot", &"")), &"unlock")
	return CHEER_OF_EVENT.get(type, &"")


## Whether cheer `a` is a better thing to say than `b` when one player gets both at once.
static func cheers_over(a: StringName, b: StringName) -> bool:
	return int(CHEER_WEIGHT.get(a, 0)) > int(CHEER_WEIGHT.get(b, 0))


static func events() -> Array:
	return moments().keys()


static func takes_of(event: StringName) -> int:
	return int(moments().get(event, {}).get("takes", 0))


static func path_of(event: StringName, n: int, voice := MALE) -> String:
	return "%s%s%s_%d.ogg" % [SoundCatalog.ROOT, VOICES[voice]["folder"], event, n]


## How long a take plays, in seconds (read once from its file).
static func length(event: StringName, n: int, voice := MALE) -> float:
	var id := take_id(event, n, voice)
	if not _lengths.has(id):
		var stream := load(path_of(event, n, voice)) as AudioStream
		_lengths[id] = stream.get_length() if stream != null else 0.0
	return _lengths[id]
