extends Node
## The generator's fuel through a night, for captures, from the player's own shoulder camera: the
## tank burning down with every circuit lit (the card shows when it runs low and when it is
## empty, the lights go out), then, where the lot sells fuel, the player at the cans with the
## prompt, buying a can, and the card showing the refill. On a branch with no fuel spots it takes
## only the burning-down views. Not part of the game. Run with Movie Maker:
## `godot --path game res://tests/captures/fuel_spots.tscn --fixed-fps 10 --write-movie out.png`.
## Each stage prints its name and the movie frame it began on.

## The tank the night starts with, so the capture does not wait a whole tank out.
const START_FUEL := 30.0
## Game seconds burnt in each movie frame while the tank runs down.
const BURN_STEP := 12.0
## Where the player stands in the yard, and the way it looks (south-east, to the cans beside it).
const YARD_SPOT := Vector3(34.3, 0.0, 15.9)
const LOOK_YAW := -PI / 2.0 - 0.7
const SETTLE_FRAMES := 12
const GIVE_UP_FRAMES := 4000

var _night: Night


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.fuel.start_fuel = START_FUEL
	tuning.rounds.first_spawn_delay = 100000.0
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().camera_rig.camera().make_current()
	_night.player().teleport(YARD_SPOT)
	_face()
	var rules := _night.server.rules
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		_act(RulesAction.set_circuit(circuit_id, true))
	_act(RulesAction.grant_points(1, 600))
	await _hold(SETTLE_FRAMES)
	_stage("burning")
	var said := {}
	while rules.generator.fuel > 0.0:
		_act(RulesAction.tick(BURN_STEP))
		_face()
		await _hold(1)
		for mark in [25.0, 10.0]:
			if rules.generator.fuel <= mark and not said.has(mark):
				said[mark] = true
				_stage("tank_%d" % int(mark))
	await _hold(SETTLE_FRAMES)
	_stage("tank_empty")
	await _hold(SETTLE_FRAMES * 2)
	_stage("tank_empty_later")
	# Untyped, so the same script also runs on a branch that has no fuel spots.
	if not "fuel" in _night.world:
		await _finish()
		return
	await _hold(SETTLE_FRAMES)
	_stage("at_the_cans")
	var use := NightCommand.new()
	use.use = true
	use.motion.yaw = LOOK_YAW
	_night.link.send(use.to_dict())
	await _hold(3)
	_stage("bought")
	await _hold(SETTLE_FRAMES)
	_stage("refilled")
	await _hold(SETTLE_FRAMES * 2)
	_stage("refilled_later")
	await _finish()


func _finish() -> void:
	await _hold(10)
	get_tree().quit()


## One tick of the night, with the player looking along `LOOK_YAW`.
func _face() -> void:
	var look := NightCommand.new()
	look.motion.yaw = LOOK_YAW
	_night.link.send(look.to_dict())
	_night.player().camera_rig.yaw = LOOK_YAW
	_night.tick()


func _stage(stage: String) -> void:
	print(
		(
			"%s at frame %d, fuel %.1f"
			% [stage, Engine.get_frames_drawn(), _night.server.rules.generator.fuel]
		)
	)


## A rules action from outside the server's tick, its events delivered as the link would.
func _act(action: Dictionary) -> void:
	_night.state.apply_events(_night.server.rules.apply(action))


## Waits `frames` rendered frames (a movie frame each).
func _hold(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
