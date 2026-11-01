extends Node3D
## Scripted capture of the sound design in a bare yard: footsteps on two surfaces, the four gun
## classes and reloads, 28 zombies groaning at once (only the loudest voices start, shown lit),
## occlusion behind a wall, the generator, and the round sting ducking the gunfire. Run with
## Movie Maker (`--write-movie out.png --fixed-fps 10`), which writes the mix to `out.wav` beside
## the frames. The markers only show who sounded.

const GROUND := Color(0.16, 0.16, 0.2)
const WALL := Color(0.55, 0.3, 0.2)
const IDLE := Color(0.18, 0.3, 0.2)
const LIT := Color(0.85, 1.0, 0.35)
const CAMERA_OFFSET := Vector3(0, 11, 9)
const WALL_BOX := AABB(Vector3(6.0, 0.0, -6.0), Vector3(1.0, 3.0, 16.0))

var _player: MeshInstance3D
var _camera: Camera3D
var _label: Label
var _duck: Label
var _zombies: Array[MeshInstance3D] = []


func _ready() -> void:
	Audio.seed_random(2026)
	_build_yard()
	Audio.listener = _player
	var ears := AudioListener3D.new()
	_player.add_child(ears)
	ears.make_current()
	await _beat("footsteps", 0.6)
	await _footsteps()
	await _guns()
	await _horde()
	await _occlusion()
	await _generator_and_sting()
	await _beat("end", 1.0)
	print("voices started: ", Audio.started, "  culled: ", Audio.culled)
	get_tree().quit()


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + CAMERA_OFFSET
	_camera.look_at(_player.global_position)
	_duck.text = "Effects ducking %.1f dB" % Audio.duck_db


# ---- the acts -----------------------------------------------------------------------------------


func _footsteps() -> void:
	_say("Footsteps: asphalt, then gravel")
	for surface in [&"step_asphalt", &"step_gravel"]:
		for i in 6:
			_player.global_position += Vector3(0.7, 0, 0)
			Audio.play(surface, _player.global_position + Vector3(0, -0.8, 0))
			await _wait(0.45)
		_player.global_position = Vector3(-4, 1, 6)
		await _wait(0.3)
	_player.global_position = Vector3(0, 1, 6)


func _guns() -> void:
	var at := _player.global_position + Vector3(0.6, 0.3, -0.6)
	_say("Pistol, SMG, rifle, shotgun")
	for entry: Array in [
		[&"shot_pistol", 3, 0.4],
		[&"shot_smg", 8, 0.09],
		[&"shot_rifle", 3, 0.55],
		[&"shot_shotgun", 2, 0.9]
	]:
		for i: int in entry[1]:
			Audio.play(entry[0], at)
			await _wait(entry[2])
		await _wait(0.5)
	_say("Reloads: pistol and shotgun, a dry click")
	Audio.play(&"dry_fire", at)
	await _wait(0.5)
	Audio.play(&"reload_pistol", at)
	await _wait(1.6)
	Audio.play(&"reload_shotgun", at)
	await _wait(2.0)


func _horde() -> void:
	_say("28 zombies groan at once: the nearest six get a voice")
	for i in 28:
		var ring := 4.0 + i * 1.1
		var angle := i * 2.4
		var zombie := _marker(
			Vector3(cos(angle) * ring, 0.9, 6.0 + sin(angle) * ring * 0.8),
			IDLE,
			Vector3(0.7, 1.8, 0.7)
		)
		_zombies.append(zombie)
	var lit := 0
	for zombie in _zombies:
		if Audio.play(&"zombie_groan", zombie.global_position) != null:
			_light(zombie, 2.4)
			lit += 1
	_say("28 zombies groan at once: %d got a voice (the nearest)" % lit)
	print("zombies given a voice: ", lit, " of ", _zombies.size())
	await _wait(2.6)
	_say("The nearest bites, is shot, falls")
	var nearest := _zombies[0]
	Audio.play(&"zombie_attack", nearest.global_position)
	await _wait(0.8)
	Audio.play(&"shot_pistol", _player.global_position + Vector3(0.6, 0.3, -0.6))
	Audio.play(&"zombie_hurt", nearest.global_position)
	await _wait(0.7)
	Audio.play(&"zombie_death", nearest.global_position)
	await _wait(2.2)
	for zombie in _zombies:
		zombie.queue_free()
	_zombies.clear()


func _occlusion() -> void:
	_say("Occlusion: the same rifle shot, open ground, then behind the wall")
	_marker(WALL_BOX.get_center() + Vector3(0, 0.0, 0), WALL, WALL_BOX.size)
	_player.global_position = Vector3(0, 1, 6)
	Audio.occlusion_probe = func(from: Vector3, to: Vector3) -> float:
		return 1.0 if WALL_BOX.intersects_segment(from, to) != null else 0.0
	var open := _marker(Vector3(-9, 0.9, 6), IDLE, Vector3(0.7, 1.8, 0.7))
	var hidden := _marker(Vector3(11, 0.9, 6), IDLE, Vector3(0.7, 1.8, 0.7))
	for i in 3:
		_light(open)
		Audio.play(&"shot_rifle", open.global_position)
		print("occlusion open at ", Engine.get_process_frames())
		await _wait(1.3)
		_light(hidden)
		Audio.play(&"shot_rifle", hidden.global_position)
		print("occlusion wall at ", Engine.get_process_frames())
		await _wait(1.3)
	Audio.occlusion_probe = Callable()


func _generator_and_sting() -> void:
	_say("The generator starts and settles into its hum")
	var generator := _marker(Vector3(-5, 0.6, 2), Color(0.9, 0.55, 0.1), Vector3(1.6, 1.2, 1.0))
	Audio.play(&"generator_start", generator.global_position)
	await _wait(3.4)
	Audio.start_loop(&"generator_hum", generator)
	await _wait(2.0)
	_say("A round begins: the sting ducks the gunfire under it")
	var at := _player.global_position + Vector3(0.6, 0.3, -0.6)
	Audio.play(&"round_start")
	for i in 14:
		Audio.play(&"shot_smg", at)
		await _wait(0.2)
	await _wait(2.0)
	_say("The round ends")
	Audio.play(&"round_end")
	await _wait(2.4)


# ---- scene --------------------------------------------------------------------------------------


func _build_yard() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.03, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	_marker(Vector3(0, -0.05, 0), GROUND, Vector3(70, 0.1, 50))
	_player = _marker(Vector3(0, 1, 6), Color(0.3, 0.55, 0.95), Vector3(0.8, 2.0, 0.8))
	_camera = Camera3D.new()
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(48, 36)
	_label.add_theme_font_size_override(&"font_size", 44)
	layer.add_child(_label)
	_duck = Label.new()
	_duck.position = Vector2(48, 110)
	_duck.add_theme_font_size_override(&"font_size", 34)
	layer.add_child(_duck)


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


func _light(marker: MeshInstance3D, seconds := 1.2) -> void:
	var material := marker.material_override as StandardMaterial3D
	material.albedo_color = LIT
	material.emission_enabled = true
	material.emission = LIT
	var tween := create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 0.0, seconds)
	tween.parallel().tween_property(material, "albedo_color", IDLE, seconds)


func _say(text: String) -> void:
	_label.text = text
	print("act: ", text, " (frame ", Engine.get_process_frames(), ")")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _beat(label: String, seconds: float) -> void:
	_say(label)
	await _wait(seconds)
