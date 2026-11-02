extends Node
## A real night (the bot plays through the loopback to the server) with the HUD and the player's
## challenges counting it, filmed through the bot's own shoulder camera: the prompt appears as
## kills and purchases cross a quarter mark, a finish or a milestone step, exactly as in the game.
## Not part of the game.
##
## Arguments after `--`: `--seconds=S` (game seconds to play, default 40), `--reduced` (reduced
## motion), `--touch` (the phone's controls on), `--marks` (start far from a finish: quarter marks
## first), `--setting=N` (0 all, 1 finished only, 2 off).
## Record: `gds godot -- --path game res://tests/captures/challenge_prompt.tscn --write-movie
## <abs>/f.png --fixed-fps 10 --quit-after N -- --seconds=60`. Prints `PROMPT <seconds> <what>`
## whenever a card appears, so the frame to look at is time x fps.
##
## The challenges are a small set made for the film: targets of a night's first minutes, in the
## words of the shipped data.

const DAY := 20401
const SAVE := "user://capture_challenges.json"
const BAKE_WAIT_FRAMES := 600

var _args := {}
var _night: Night
var _hud: Hud
var _ticks := 0


func _ready() -> void:
	_args = _parse_args()
	UIMotion.reduced = _args.has("reduced")
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	_hud.challenge.cue.connect(
		func(finished: bool) -> void:
			print(
				(
					"PROMPT %.1f %s %s"
					% [
						_ticks / 60.0,
						"finish" if finished else "mark",
						_hud.challenge.queue.current.get("text")
					]
				)
			)
	)
	if _args.has("touch"):
		# The phone's layout, as the night screen builds it (the `--touch` flag turns the controls on).
		var touch := TouchControls.new()
		touch.state = _hud.state
		add_child(touch)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var board := ChallengeBoard.open(SAVE, ChallengeFixture.clock_on(DAY), _catalog())
	_night = Night.new()
	_night.hud = _hud
	_night.challenge_board = board
	add_child(_night)
	_night.shoulder_camera = true
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 3.0
	tuning.economy.item(&"door_concession").price = 250
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, tuning)
	_hud.challenge.mode = int(_args.get("setting", 0)) as HudChallenge.Mode
	_seed_progress(board)
	_night.ticked.connect(_on_tick)


## Dailies, orders and ladders in the shipped words, with targets a night's first minutes reach.
func _catalog() -> ChallengeCatalog:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				_record("d_kills", "Put down {n} zombies", "kills", 12, "short", "kills"),
				_record("d_head", "Land {n} headshot kills", "kills:head", 8, "medium", "aim"),
				_record(
					"d_round",
					"Reach round {n} in one night",
					"round",
					3,
					"long",
					"survive",
					"night"
				),
			],
			ChallengeDef.Family.DAILY
		)
	)
	(
		catalog
		. add_all(
			[
				_record(
					"o_pistol",
					"Put down {n} zombies with the pistol",
					"kills:weapon:pistol",
					20,
					"medium",
					"",
					"total",
					"craft"
				),
				_record(
					"o_doors",
					"Open {n} ways through in one night",
					"doors_bought",
					2,
					"short",
					"",
					"night",
					"night"
				),
				_record(
					"o_boards",
					"Mend {n} boards",
					"boards_repaired",
					30,
					"medium",
					"",
					"total",
					"light"
				),
			],
			ChallengeDef.Family.ORDER
		)
	)
	(
		catalog
		. add_all(
			[
				{
					"id": "m_kills",
					"text": "Put down {n} zombies",
					"stat": "kills",
					"steps": [10, 50, 250]
				},
				{
					"id": "m_rounds",
					"text": "Get through {n} rounds",
					"stat": "rounds",
					"steps": [1, 10, 50]
				},
			],
			ChallengeDef.Family.MILESTONE
		)
	)
	return catalog


func _record(
	id: String,
	text: String,
	stat: String,
	target: int,
	tier: String,
	group: String,
	mode := "total",
	pillar := ""
) -> Dictionary:
	return {
		"id": id,
		"text": text,
		"stat": stat,
		"target": target,
		"tier": tier,
		"group": group,
		"mode": mode,
		"pillar": pillar,
		"reward": {},
	}


## A player part-way through: the first mark of a daily is a few kills away.
func _seed_progress(board: ChallengeBoard) -> void:
	for entry in board.profile.dailies:
		if entry["id"] == &"d_kills":
			entry["progress"] = 2 if _args.has("marks") else 9
		if entry["id"] == &"d_head":
			entry["progress"] = 5
	board.profile.lifetime[&"kills"] = 0 if _args.has("marks") else 8


func _on_tick() -> void:
	_ticks += 1
	if not _night.running:
		return
	if _ticks / 60.0 >= float(_args.get("seconds", 40)) or _night.state.over:
		_finish()


func _finish() -> void:
	_night.running = false
	for _i in BAKE_WAIT_FRAMES:
		if not _night.world.navigation.is_busy():
			break
		await get_tree().physics_frame
	Audio.stop_all()
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		var text := argument.trim_prefix("--")
		var at := text.find("=")
		parsed[text.substr(0, at) if at >= 0 else text] = text.substr(at + 1) if at >= 0 else true
	return parsed
