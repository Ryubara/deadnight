extends Node3D
## Scripted capture of the dead's sound: a horde (walkers, runners, a brute, a crawler) closing on
## a listener from the front, behind, the left and the right, then the headliner's entrance, blow
## and fall. The zombies are fed to `ZombieVoices` as the entries a client decodes from a frame,
## so what is recorded is the real service and the real mix. Run with Movie Maker
## (`--write-movie out.png --fixed-fps 10`, which writes the mix to `out.wav`); the markers only
## show who is where, and prints give the voice counts the analysis checks.

const PHYSICS_STEP := 1.0 / 60.0
## The listener looks down -Z; each act's horde starts this many metres out.
const START_RADIUS := 24.0
const STOP_RADIUS := 2.2
const ACTS: Array[Dictionary] = [
	{"name": "From the front", "dir": Vector3(0, 0, -1), "seconds": 10.0},
	{"name": "From behind", "dir": Vector3(0, 0, 1), "seconds": 10.0},
	{"name": "From the left", "dir": Vector3(-1, 0, 0), "seconds": 10.0},
	{"name": "From the right", "dir": Vector3(1, 0, 0), "seconds": 10.0},
]
const LOOKS: Array[StringName] = [&"walker", &"runner", &"walker", &"brute", &"crawler", &"walker"]
const SPEEDS := {&"walker": 2.4, &"runner": 4.2, &"brute": 1.8, &"crawler": 1.2}
const COLORS := {
	&"walker": Color(0.35, 0.55, 0.3),
	&"runner": Color(0.85, 0.5, 0.2),
	&"brute": Color(0.6, 0.25, 0.25),
	&"crawler": Color(0.5, 0.5, 0.6),
	&"headliner": Color(0.9, 0.2, 0.9),
}

var _voices: ZombieVoices
var _player: MeshInstance3D
var _camera: Camera3D
var _label: Label
var _stats: Label
var _markers: Dictionary[int, MeshInstance3D] = {}
var _zombies: Array[Dictionary] = []
var _time := 0.0
var _act := -1
var _act_start := 0.0
var _boss_start := -1.0
var _max_voice := 0
var _max_step := 0
var _max_all := 0
var _next_id := 1


func _ready() -> void:
	Audio.seed_random(2026)
	_build()
	Audio.listener = _player
	var ears := AudioListener3D.new()
	_player.add_child(ears)
	ears.make_current()
	_voices = ZombieVoices.new(Audio, 11)
	_voices.windups = {&"headliner": 1.2}


func _physics_process(delta: float) -> void:
	_time += delta
	var total := 0.0
	for act in ACTS:
		total += float(act["seconds"])
	if _boss_start < 0.0 and _time >= total:
		_boss_start = _time
		_start_boss()
	if _boss_start < 0.0:
		_run_acts()
	else:
		_run_boss()
	var entries: Array[Dictionary] = []
	for zombie in _zombies:
		entries.append(_entry(zombie))
	_voices.update(entries, delta)
	_show(entries)
	var budget := Audio.budget_3d()
	_max_voice = maxi(_max_voice, budget.group_count(&"zombie_voice"))
	_max_step = maxi(_max_step, budget.group_count(&"zombie_step"))
	_max_all = maxi(_max_all, budget.active_count())
	_stats.text = (
		"zombie voices %d/6   feet %d/5   all %d/32   started %d  culled %d"
		% [
			budget.group_count(&"zombie_voice"),
			budget.group_count(&"zombie_step"),
			budget.active_count(),
			Audio.started,
			Audio.culled
		]
	)
	if _boss_start >= 0.0 and _time - _boss_start > 14.0:
		print(
			"max zombie voices: ",
			_max_voice,
			"  max feet: ",
			_max_step,
			"  max all: ",
			_max_all,
			"  started: ",
			Audio.started,
			"  culled: ",
			Audio.culled
		)
		print("requested: ", _voices.requested)
		get_tree().quit()


func _run_acts() -> void:
	var at := 0.0
	var index := 0
	for act in ACTS:
		if _time < at + float(act["seconds"]):
			break
		at += float(act["seconds"])
		index += 1
	if index != _act:
		_act = index
		_act_start = _time
		_zombies.clear()
		_label.text = "Horde " + String(ACTS[index]["name"]).to_lower()
		print("act: ", _label.text, " at ", snappedf(_time, 0.01))
		_spawn_horde(ACTS[index]["dir"])
	for zombie in _zombies:
		_advance(zombie)


func _spawn_horde(dir: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	for i in LOOKS.size() * 2:
		var look := LOOKS[i % LOOKS.size()]
		var along := (float(i) - LOOKS.size()) * 1.6
		var radius := START_RADIUS + float(i) * 0.9
		(
			_zombies
			. append(
				{
					"id": _next_id,
					"look": look,
					"pos": dir * radius + side * along,
					"mode": ZombieBody.Mode.CHASE,
					"episode": 0,
					"clock": 0.0,
					"speed": SPEEDS[look],
				}
			)
		)
		_next_id += 1


func _advance(zombie: Dictionary) -> void:
	var pos: Vector3 = zombie["pos"]
	var to := -pos
	to.y = 0.0
	if zombie["mode"] == ZombieBody.Mode.CHASE:
		if to.length() > STOP_RADIUS:
			zombie["pos"] = pos + to.normalized() * float(zombie["speed"]) * PHYSICS_STEP
		else:
			zombie["mode"] = ZombieBody.Mode.ATTACK
			zombie["episode"] += 1
			zombie["clock"] = 0.0
	elif zombie["mode"] == ZombieBody.Mode.ATTACK:
		zombie["clock"] += PHYSICS_STEP
		if zombie["clock"] >= 1.2:
			zombie["clock"] = 0.0
			zombie["episode"] += 1


func _start_boss() -> void:
	_zombies.clear()
	_label.text = "The headliner"
	print("act: ", _label.text, " at ", snappedf(_time, 0.01))
	(
		_zombies
		. append(
			{
				"id": _next_id,
				"look": &"headliner",
				"pos": Vector3(-9.0, 0, -14.0),
				"mode": ZombieBody.Mode.EMERGING,
				"episode": 0,
				"clock": 0.0,
				"speed": 0.0,
			}
		)
	)
	_next_id += 1


func _run_boss() -> void:
	var boss := _zombies[0]
	var since := _time - _boss_start
	if since > 2.75 and boss["mode"] == ZombieBody.Mode.EMERGING:
		boss["mode"] = ZombieBody.Mode.CHASE
		boss["speed"] = 0.9
	if boss["mode"] == ZombieBody.Mode.CHASE:
		var pos: Vector3 = boss["pos"]
		var to := -pos
		to.y = 0.0
		if to.length() > 3.0:
			boss["pos"] = pos + to.normalized() * 3.5 * PHYSICS_STEP
		else:
			boss["mode"] = ZombieBody.Mode.ATTACK
			boss["episode"] += 1
			boss["speed"] = 0.0
			boss["clock"] = 0.0
			print("boss swings at ", snappedf(_time - _boss_start, 0.01))
	elif boss["mode"] == ZombieBody.Mode.ATTACK:
		boss["clock"] += PHYSICS_STEP
		if boss["clock"] > 1.9:
			boss["mode"] = ZombieBody.Mode.DYING
			boss["episode"] += 1
			print("boss falls at ", snappedf(_time - _boss_start, 0.01))


func _entry(zombie: Dictionary) -> Dictionary:
	return {
		"id": zombie["id"],
		"position": zombie["pos"],
		"yaw": 0.0,
		"mode": zombie["mode"],
		"episode": zombie["episode"],
		"speed": zombie["speed"] if zombie["mode"] == ZombieBody.Mode.CHASE else 0.0,
		"look": zombie["look"],
	}


func _show(entries: Array[Dictionary]) -> void:
	var seen := {}
	for entry in entries:
		var id: int = entry["id"]
		seen[id] = true
		if not _markers.has(id):
			var size := Vector3(1.6, 2.4, 1.6) * (1.6 if entry["look"] == &"headliner" else 1.0)
			_markers[id] = _marker(entry["position"], COLORS[entry["look"]], size)
		var marker := _markers[id]
		marker.global_position = entry["position"] + Vector3(0, 0.9, 0)
	for id: int in _markers.keys():
		if not seen.has(id):
			_markers[id].queue_free()
			_markers.erase(id)


func _build() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.03, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	_marker(Vector3(0, -0.05, 0), Color(0.16, 0.16, 0.2), Vector3(80, 0.1, 80))
	_player = _marker(Vector3(0, 1, 0), Color(0.3, 0.55, 0.95), Vector3(0.8, 2.0, 0.8))
	var nose := _marker(Vector3(0, 1.3, -0.7), Color(1, 1, 1), Vector3(0.3, 0.3, 0.6))
	nose.reparent(_player)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.global_position = Vector3(0, 40, 6)
	_camera.look_at(Vector3(0, 0, 3), Vector3.FORWARD)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(48, 36)
	_label.add_theme_font_size_override(&"font_size", 48)
	layer.add_child(_label)
	_stats = Label.new()
	_stats.position = Vector2(48, 110)
	_stats.add_theme_font_size_override(&"font_size", 32)
	layer.add_child(_stats)


func _marker(at: Vector3, color: Color, size: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
	mesh.global_position = at
	return mesh
