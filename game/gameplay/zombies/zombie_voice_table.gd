class_name ZombieVoiceTable
extends RefCounted
## Which sounds each zombie look uses, and how its feet keep time. Plain data: `ZombieVoices` reads
## it and plays; nothing here touches the audio service. The sounds are `SoundCatalog`'s; why each
## type sounds as it does is `docs/design/audio.md`.

## What a look says, by role:
## - `idle`: the sounds it makes now and then while it walks (one picked at random);
## - `alert`: the cue when it has noticed a player, or `&""` for none;
## - `swing`: the effort of a blow, started so that its peak (`swing_lead`, seconds into the file)
##   lands on the blow;
## - `windup`: the type's own swing cue when it winds up for longer than a walker's blow (the boss);
## - `hurt`, `death`: when it is shot and when it falls;
## - `step`: what its feet sound like at a walk and at a run (`run_from` m/s and up);
## - `lift`: how high its mouth is above its feet in metres (the sound's place).
const WALKER := {
	"idle": [&"zombie_groan"],
	"alert": &"zombie_alert",
	"swing": &"zombie_grunt",
	"swing_lead": 0.07,
	"hurt": &"zombie_hurt",
	"death": &"zombie_death",
	"step": &"zombie_step_shuffle",
	"step_run": &"zombie_step_run",
	"run_from": 2.2,
	"lift": 1.9,
}

const LOOKS := {
	&"runner": {"alert": &"zombie_shriek", "lift": 2.0},
	&"brute":
	{
		"idle": [&"zombie_breath_brute", &"zombie_breath_brute", &"zombie_groan_brute"],
		"alert": &"zombie_groan_brute",
		"swing": &"zombie_attack",
		"swing_lead": 0.12,
		"step": &"zombie_step_stomp",
		"step_run": &"zombie_step_stomp",
		"lift": 2.3,
	},
	&"crawler":
	{
		"idle": [&"zombie_groan_crawler"],
		"step": &"zombie_drag",
		"step_run": &"zombie_drag",
		"lift": 0.5,
	},
	&"headliner":
	{
		"idle": [&"zombie_groan_brute"],
		"alert": &"",
		"swing": &"zombie_growl_boss",
		"swing_lead": 0.92,
		"step": &"zombie_step_stomp",
		"step_run": &"zombie_step_stomp",
		"lift": 3.2,
	},
}

## The animation clips' lengths in seconds (clips.json beside each model, docs/design/zombies.md):
## a footstep falls at every half of a cycle (a foot plants twice in a walk, run, crawl or boss
## walk), so the cadence is a clip's length over two.
const WALK_CYCLE := 1.3333
const RUN_CYCLE := 0.6667
const CRAWL_CYCLE := 1.6667
const BOSS_CYCLE := 1.6667
## The move blend: walk below `WALK_AT` m/s, fully run at `RUN_AT` (`ZombieRig`).
const WALK_AT := 1.0
const RUN_AT := 3.0
## Slower than this a zombie is standing, and its feet are silent.
const MOVING_FROM := 0.3


## The role `key` of `look`, falling back to the walker's.
static func get_role(look: StringName, key: String) -> Variant:
	var own: Dictionary = LOOKS.get(look, {})
	return own[key] if own.has(key) else WALKER[key]


## Seconds of one cycle of the clip that plays at `speed` for `look`.
static func cycle_seconds(look: StringName, speed: float) -> float:
	if ZombieModels.crawls(look):
		return CRAWL_CYCLE
	if ZombieModels.is_boss(look):
		return BOSS_CYCLE
	var run := clampf((speed - WALK_AT) / (RUN_AT - WALK_AT), 0.0, 1.0)
	return lerpf(WALK_CYCLE, RUN_CYCLE, run)


## The step sound a zombie of `look` makes at `speed`.
static func step_sound(look: StringName, speed: float) -> StringName:
	if speed >= float(get_role(look, "run_from")):
		return get_role(look, "step_run")
	return get_role(look, "step")
