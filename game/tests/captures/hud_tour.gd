extends Node
## Scripted capture of the HUD over the lot at night. A real `GameRules` night is driven by actions
## and every event it returns goes to the HUD (the same path a client takes from the server), with
## the local player's own readings and the world markers set beside them.
##
## Run with Movie Maker: `godot --path game res://tests/captures/hud_tour.tscn --write-movie out.png
## --fixed-fps 10 --resolution 1280x720 -- --view=concession --fonts=<fonts folder> [--reduced]`.
## `--fonts` loads the Marquee pairing from a folder of font files kept outside the repository; with
## none the HUD uses the engine fallback. Stage times are printed so a frame can be found:
## frame = time x fps.

const RULES_TUNING := "res://gameplay/rules/default_tuning.tres"
## More than any zombie has.
const KILLING_DAMAGE := 99999.0
const NAMES := {1: "Ruby", 2: "Moe", 3: "Dee"}

var _rules: GameRules
var _hud: Hud
var _clock := 0.0
var _tuning: RulesTuning


func _ready() -> void:
	var args := _args()
	UIMotion.reduced = args.has("reduced")
	_load_fonts(str(args.get("fonts", "")))
	var rig := (load("res://world/drive_in/capture_rig.tscn") as PackedScene).instantiate()
	add_child(rig)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	await get_tree().process_frame
	await _run()
	print("hud tour done at %.1f s" % _clock)
	get_tree().quit()


func _run() -> void:
	var tuning := (load(RULES_TUNING) as RulesTuning).duplicate(true)
	tuning.fuel.start_fuel = 34.0
	_tuning = tuning
	_rules = GameRules.new(tuning, 1958)
	_hud.state.configure(
		tuning.fuel.capacity, tuning.fuel.circuit_drain.keys(), tuning.fuel.start_circuits
	)
	_hud.state.fuel = tuning.fuel.start_fuel
	_hud.state.fuel_capacity = tuning.fuel.capacity
	_hud.state.set_health(100.0, 100.0)
	_hud.state.set_ammo(30, 150, "Rifle")
	_hud.state.set_equipment("Flare", 2)
	_hud.state.set_area("The Lot", "Open the concession stand")
	for player_id in NAMES:
		_hud.state.set_player_name(player_id, NAMES[player_id])
	_mark("night opens")
	for player_id in NAMES:
		_do(RulesAction.add_player(player_id))
		await _wait(0.4)
	_do(RulesAction.start())
	_do(RulesAction.skip_break())
	(
		_hud
		. state
		. set_markers(
			(
				[
					_marker(&"door", &"objective", 0.62, 0.52, 19.0, "Concession", true),
					_marker(&"moe", &"ally", 0.3, 0.55, 12.0, "Moe", false),
				]
				as Array[Dictionary]
			)
		)
	)
	_mark("round 1 banner")
	await _wait(3.2)
	await _fight()
	await _hurt()
	await _shop()
	await _fuel()
	await _down()
	await _end()


## Zombies spawn and fall: hit numbers, hit markers, kill gains stacking beside the crosshair.
func _fight() -> void:
	_mark("fight")
	var ids: Array[int] = []
	for _i in 60:
		for event in _step(0.1):
			if event["type"] == &"zombie_spawn_requested":
				ids.append(int(event["zombie_id"]))
		if ids.size() >= 3:
			break
	_do(RulesAction.hit(1, ids[0], RulesAction.ZONE_BODY, 18.0))
	_hud.state.set_ammo(27, 150)
	await _wait(0.3)
	_do(RulesAction.hit(1, ids[0], RulesAction.ZONE_HEAD, 30.0))
	await _wait(0.2)
	_do(RulesAction.hit(1, ids[1], RulesAction.ZONE_HEAD, 90.0))
	_hud.state.set_ammo(24, 150)
	await _wait(0.5)
	_do(RulesAction.hit(1, ids[0], RulesAction.ZONE_BODY, KILLING_DAMAGE))
	await _wait(0.4)
	_do(RulesAction.hit(1, ids[2], RulesAction.ZONE_HEAD, KILLING_DAMAGE))
	_hud.state.set_ammo(4, 150)
	_mark("gains stacked, ammo low")
	await _wait(1.6)


## Blows land from several sides, health falls into the red.
func _hurt() -> void:
	_mark("hurt")
	var health := 100.0
	for angle in [0.9, -1.6, 3.0, 0.2]:
		health -= 21.0
		(
			_hud
			. state
			. apply_event(
				{
					"type": HudState.PLAYER_HURT,
					"player_id": 1,
					"health": health,
					"direction": angle,
					"amount": 21.0,
				}
			)
		)
		await _wait(0.35)
	await _wait(1.2)
	_hud.state.set_health(60.0)


## The prompt: out of reach of the price, then paid, the key held, a door refused and one opened.
func _shop() -> void:
	_mark("prompt, cannot afford")
	_hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
	await _wait(1.4)
	_do(RulesAction.grant_points(1, 400, &"grant"))
	_mark("prompt, affordable")
	await _wait(0.8)
	Input.action_press(&"interact")
	_mark("interact held")
	await _wait(0.5)
	Input.action_release(&"interact")
	_do(RulesAction.buy(1, &"door_booth"))
	_mark("refused: the concession comes first")
	await _wait(2.0)
	_hud.state.set_prompt(&"buy_door", "Concession door", 350)
	await _wait(0.6)
	_do(RulesAction.buy(1, &"door_concession"))
	await _wait(1.6)
	_hud.state.set_area("The Concession Stand", "Light the booth")


## The tank runs low, then dry; a circuit goes out.
func _fuel() -> void:
	_mark("fuel low")
	_do(RulesAction.set_circuit(&"booth", true))
	_tuning.fuel.idle_drain = 2.5
	while not _hud.state.fuel_low:
		await _wait(0.1)
	await _wait(1.8)
	_tuning.fuel.idle_drain = 12.0
	while not _hud.state.fuel_empty:
		await _wait(0.1)
	_mark("fuel empty")
	await _wait(1.8)


## A teammate goes down and leaves; you go down; then someone pulls you up.
func _down() -> void:
	_mark("down")
	_do(RulesAction.set_downed(2, true))
	await _wait(0.8)
	_hud.state.set_player_name(4, "Cal")
	_do(RulesAction.add_player(4))
	await _wait(0.8)
	_do(RulesAction.remove_player(4))
	await _wait(0.8)
	_hud.state.set_health(0.0)
	_do(RulesAction.set_downed(1, true))
	await _wait(1.6)
	_do(RulesAction.set_downed(1, false))
	_hud.state.set_health(40.0)
	await _wait(0.8)


func _end() -> void:
	_mark("round over, then the night")
	_hud.state.apply_event({"type": &"round_ended", "round": 1})
	await _wait(3.4)
	_hud.state.apply_event({"type": &"game_over", "reason": &"all_down", "round_reached": 1})
	await _wait(3.4)


func _do(action: Dictionary) -> void:
	_hud.feed(_rules.apply(action))


func _step(seconds: float) -> Array[Dictionary]:
	var events := _rules.apply(RulesAction.tick(seconds))
	_hud.feed(events)
	return events


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		var step := get_process_delta_time()
		left -= step
		_clock += step
		_hud.feed(_rules.apply(RulesAction.tick(minf(step, 0.5))))


func _mark(stage: String) -> void:
	print("t=%.1f  %s" % [_clock, stage])


static func _marker(
	id: StringName,
	kind: StringName,
	x: float,
	y: float,
	distance: float,
	label: String,
	important: bool
) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"x": x,
		"y": y,
		"distance": distance,
		"label": label,
		"important": important,
	}


func _load_fonts(folder: String) -> void:
	if folder == "":
		return
	var pairing: Dictionary = TypographyPairings.ALL[0]
	var tokens := UITokens.active()
	tokens.font_display = TypographyPairings.load_face(pairing["display"], folder)
	tokens.font_text = TypographyPairings.load_face(pairing["text"], folder)


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := arg.trim_prefix("--")
		var parts := text.split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
