extends Node
## The HUD over a night where a zombie stands at the player's right hand and strikes until the
## health is low, then the player is left alone and health mends. Not part of the game. Run with
## Movie Maker: `godot --path game res://tests/captures/night_hud_blow.tscn --fixed-fps 10
## --write-movie out.png --quit-after 700`.

## Metres to the player's right where the zombie is held.
const BESIDE := Vector3(0.8, 0.0, 0.0)
const STRIKE_TICKS := 420
const MEND_TICKS := 420

var _night: Night


func _ready() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	# From outside the server's tick, so its events are delivered as the link would.
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	var zombie_id := -1
	while zombie_id == -1:
		await get_tree().physics_frame
		if not _night.server.sim.zombies.is_empty():
			zombie_id = _night.server.sim.zombies.keys()[0]
	print("a zombie is on the lot")
	for _i in STRIKE_TICKS:
		var body: ZombieBody = _night.server.sim.zombies.get(zombie_id)
		if body != null:
			body.position = _night.state.position() + BESIDE
		await get_tree().physics_frame
	print("health %.0f after the blows" % _night.server.health_of(1))
	_night.server.sim.zombies[zombie_id].position = _night.state.position() + Vector3(0, 0, -60)
	for _i in MEND_TICKS:
		await get_tree().physics_frame
	print("health %.0f after mending" % _night.server.health_of(1))
	get_tree().quit()
