extends Node
## Capture of the point gains and the event list stacking: three lines arrive, the oldest leaves,
## and the lines below slide up into its place (before the change they jumped). The HUD is over the
## lot and is fed the way a night feeds it; the lines are added by hand at set times so the
## frames show the slide.
##
## Run with Movie Maker: `godot --path game res://tests/captures/hud_gains_slide.tscn --write-movie
## out.png --fixed-fps 30 --quit-after 170`. The oldest gain leaves at 2.7 s: frame = time x fps.

const RULES_TUNING := "res://gameplay/rules/default_tuning.tres"

var _hud: Hud
var _clock := 0.0


func _ready() -> void:
	var rig := (load("res://world/drive_in/capture_rig.tscn") as PackedScene).instantiate()
	add_child(rig)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _run() -> void:
	var tuning := (load(RULES_TUNING) as RulesTuning).duplicate(true)
	_hud.state.configure(
		tuning.fuel.capacity, tuning.fuel.circuit_drain.keys(), tuning.fuel.start_circuits
	)
	_hud.state.set_health(100.0, 100.0)
	_hud.state.set_ammo(30, 150, "Rifle")
	_hud.state.set_area("The Lot", "Open the concession stand")
	_hud.state.set_player_name(1, "Ruby")
	await _wait(0.3)
	_hud.gains.add_gain(&"headshot_kill", 100)
	_hud.events_feed.push("RUBY OPENED THE CONCESSION STAND")
	await _wait(0.6)
	_hud.gains.add_gain(&"kill", 60)
	_hud.events_feed.push("MOE IS DOWN")
	await _wait(0.6)
	_hud.gains.add_gain(&"round_bonus", 50)
	_hud.events_feed.push("GENERATOR RUNNING LOW")
	await _wait(3.8)


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		var step := get_process_delta_time()
		left -= step
		_clock += step
