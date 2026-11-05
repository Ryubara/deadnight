extends Node
## A real night (the bot plays through the loopback to the server) with the HUD and the player's
## shipped challenges counting it (#1074): a board that has put down zombies with four weapons and
## a door that costs what the bot can pay at once, so the card for "Open a door in the first thirty
## seconds of a night" and the card for "Put down zombies with five different weapons" come up as
## the bot plays, in the game's own words. Not part of the game.
##
## Arguments after `--`: `--seconds=S` (game seconds to play, default 40).
## Record: `gds godot -- --path game res://tests/captures/challenge_moments_prompt.tscn
## --write-movie <abs>/f.png --fixed-fps 10 --quit-after N -- --seconds=40`. Prints `DONE <seconds>
## <id>` for each challenge the bot finishes, so the frame to look at is time x fps.

const DAY := 20401
const SAVE := "user://capture_challenge_moments.json"
const BAKE_WAIT_FRAMES := 600
## The weapons the board has already put zombies down with: the bot's start weapon is the fifth.
const KNOWN: Array[StringName] = [&"smg", &"shotgun", &"rifle", &"crowbar"]

var _args := {}
var _night: Night
var _hud: Hud
var _ticks := 0


func _ready() -> void:
	_args = _parse_args()
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
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var board := ChallengeBoard.open(SAVE, ChallengeFixture.clock_on(DAY))
	for weapon in KNOWN:
		board.profile.lifetime[ChallengeStats.weapon_kills(weapon)] = 3
	_night = Night.new()
	_night.hud = _hud
	_night.challenge_board = board
	add_child(_night)
	_night.shoulder_camera = true
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 3.0
	tuning.economy.item(&"door_concession").price = 150
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, tuning)
	_night.challenges.advanced.connect(
		func(advance: Dictionary) -> void:
			if advance["completed"]:
				print("DONE %.1f %s" % [_ticks / 60.0, advance["id"]])
	)
	_night.ticked.connect(_on_tick)


func _on_tick() -> void:
	_ticks += 1
	if not _night.running:
		return
	if _ticks / 60.0 >= float(_args.get("seconds", 40)) or _night.state.over:
		_finish()


func _finish() -> void:
	_night.running = false
	var profile := _night.challenge_board.profile
	print(
		"FEATS ",
		profile.feats,
		" DOORS ",
		profile.lifetime.get(&"doors_bought", 0),
		" BUYS ",
		profile.lifetime.get(&"buys", 0)
	)
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
