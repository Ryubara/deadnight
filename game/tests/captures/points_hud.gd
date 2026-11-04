extends Node
## Capture of the score HUD fed by the real rules (Deadnight #916): a runner and two walkers shot
## in the head and the body and killed, so the gains list and the points box show what a player
## sees. Every amount in the frame is a multiple of 5.
##
## Run: `gds godot -- --path game res://tests/captures/points_hud.tscn -- --out=<abs path>` (no
## `.png`). It writes `<out>_walker.png` and `<out>_runner.png` and prints the gains and the total.

const RULES_TUNING := "res://gameplay/rules/default_tuning.tres"

var _hud: Hud
var _rules: GameRules


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
	_hud.state.set_ammo(6, 36, "Revolver")
	_hud.state.set_area("The Lot", "Open the concession stand")
	_hud.state.set_player_name(1, "Ruby")
	_rules = GameRules.new(tuning, 7)
	_hud.feed(_rules.apply(RulesAction.add_player(1)))
	_hud.feed(_rules.apply(RulesAction.start()))
	_hud.feed(_rules.apply(RulesAction.skip_break()))
	_rules._plan.assign([&"walker", &"runner"])
	for _i in 3600:
		_hud.feed(_rules.apply(RulesAction.tick(1.0 / 60.0)))
		if _rules.zombie_ids().size() >= 2:
			break
	var ids := _rules.zombie_ids()
	ids.sort()
	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			prefix = arg.trim_prefix("--out=")
	# A walker: two hits to the body, two to the head, then the kill with the head.
	_shoot(ids[0], RulesAction.ZONE_BODY, 5.0)
	_shoot(ids[0], RulesAction.ZONE_BODY, 5.0)
	_shoot(ids[0], RulesAction.ZONE_HEAD, 5.0)
	_shoot(ids[0], RulesAction.ZONE_HEAD, 5.0)
	_shoot(ids[0], RulesAction.ZONE_HEAD, RulesFixture.KILLING_DAMAGE)
	await _wait(0.6)
	_save(prefix + "_walker.png")
	# A runner (pays 1.2 times): one hit to the body, then the kill.
	_shoot(ids[1], RulesAction.ZONE_BODY, 5.0)
	_shoot(ids[1], RulesAction.ZONE_BODY, RulesFixture.KILLING_DAMAGE)
	await _wait(0.6)
	_save(prefix + "_runner.png")


func _save(path: String) -> void:
	print("POINTS total=%d gains=%s" % [_rules.points_of(1), _hud.gains.texts()])
	if path.begins_with("_"):
		return
	get_viewport().get_texture().get_image().save_png(path)


func _shoot(zombie_id: int, zone: StringName, damage: float) -> void:
	_hud.feed(_rules.apply(RulesAction.hit(1, zombie_id, zone, damage)))


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
