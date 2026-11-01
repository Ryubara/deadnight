class_name NightWarmup
extends Node
## Pays for the first use of everything a night draws and sounds, behind the loading screen, so the
## night itself never stops to do it. In the Compatibility renderer (the web build is WebGL2) the
## engine builds a GL program the first time a kind of mesh is drawn with a kind of material under a
## kind of light, and loads a file the first time it is asked for; both happen in the middle of a
## frame. Neither the shader baker nor ubershaders exist there, so the way is the old one: draw
## everything once, out of sight (`docs/research/first-use-hitches.md`).
##
## What it does, in order, each step a few frames behind `progress`:
##   1. loads every scene and resource the catalogues name (`WarmupManifest`) and holds on to them,
##      because a resource nothing references is freed and read again at its next use;
##   2. loads every sound's files into the audio service's cache;
##   3. draws the whole lot from above with every lamp lit, then with every lamp dark (the
##      programs of a mesh differ with the lights that reach it, and the generator can fail);
##   4. on a stage high above the lot, in each of four light conditions (the moon alone, an omni
##      light, a spot light, both): every zombie look near and far, every weapon's and grenade's
##      scene, and the night view's own effects, replayed from sample events (a shot of each weapon,
##      damage numbers with every digit, a blast), and keeps the materials those effects made, so
##      the shaders they own are not freed with the short-lived nodes (a shader goes with the last
##      material that uses it, and would be built again at every shot).
## The night's lights, environment and fog are used as they are: the stage is in the same world,
## seen through a camera of its own that is current for the warm-up.

## Fraction (0 to 1) done and what is being done.
signal progress(fraction: float, text: String)

## The stage is this high above the lot, out of reach of every lamp.
const STAGE_HEIGHT := 150.0
## How far the zombies in a row stand apart.
const ROW_SPACING := 1.9
## Camera distances for the near shot (the near meshes) and the far one (past
## `ZombieModels.FAR_FROM`).
const NEAR_SHOT := 9.0
const FAR_SHOT := 34.0
const SHOT_FOV := 75.0
## The light conditions every thing is drawn under: whether an omni and a spot light reach it.
const LIGHT_CELLS: Array[Dictionary] = [
	{"label": "moonlight", "omni": false, "spot": false},
	{"label": "an omni light", "omni": true, "spot": false},
	{"label": "a spot light", "omni": false, "spot": true},
	{"label": "both", "omni": true, "spot": true},
]
## Share of the bar each step takes.
const WEIGHTS := {"load": 0.30, "sounds": 0.10, "lot": 0.20, "stage": 0.40}
## Milliseconds a frame may spend loading sounds, so the bar keeps moving.
const SOUND_BUDGET_MSEC := 8
## Frames each shot is held, so the draw reaches the screen (and the renderer builds what it needs).
const SHOT_FRAMES := 2
## Digits of the damage numbers: every glyph the numbers use is drawn once.
## Zombie bodies made before the night, by look: the walkers' four looks come most (more are made
## as the night needs them, and kept).
const PARKED_BODIES := {
	&"walker": 6,
	&"greaser": 4,
	&"usher": 4,
	&"farmhand": 4,
	&"runner": 3,
	&"brute": 3,
	&"crawler": 3
}
const DIGITS_NUMBER := 1234567890
const BUSES_MUTED: Array[StringName] = [&"Effects", &"Voice"]

## What was drawn: the warm-up records its tree after every shot.
var ledger := DrawLedger.new()
## Frames the warm-up drew, for tests.
var shots := 0
## The box around the lot that the lot pass looked at.
var lot_bounds := AABB()

var _night: Night
var _camera: Camera3D
var _before: Camera3D
## Everything the night will want again, held so it stays loaded (resources, effect materials).
var _pins: Array = []
var _stage: Node3D
var _done := 0.0


## Runs every step; the night is not running meanwhile. The caller waits for it.
func run(night: Night) -> void:
	_night = night
	_before = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = SHOT_FOV
	add_child(_camera)
	_camera.make_current()
	var muted := _mute()
	await _load_resources()
	await _load_sounds()
	await _lot_pass()
	await _stage_pass()
	_say(_done, "Rousing the dead")
	_night.view.horde.prewarm(PARKED_BODIES)
	await get_tree().process_frame
	_unmute(muted)
	if is_instance_valid(_before):
		_before.make_current()
	_camera.queue_free()
	if _stage != null:
		_stage.queue_free()
	_say(1.0, "Ready")


## What the warm-up holds on to: a test looks that the catalogue's files are among them.
func pinned_paths() -> Array[String]:
	var paths: Array[String] = []
	for pin in _pins:
		if pin is Resource and (pin as Resource).resource_path != "":
			paths.append((pin as Resource).resource_path)
	return paths


func _load_resources() -> void:
	var paths := WarmupManifest.resource_paths()
	var requested: Array[String] = []
	for path in paths:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			requested.append(path)
	var waiting := requested.duplicate()
	while not waiting.is_empty():
		var still: Array[String] = []
		for path in waiting:
			match ResourceLoader.load_threaded_get_status(path):
				ResourceLoader.THREAD_LOAD_LOADED:
					_pins.append(ResourceLoader.load_threaded_get(path))
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					still.append(path)
				_:
					push_warning("NightWarmup: could not load %s" % path)
		waiting = still
		var share := 1.0 - float(waiting.size()) / maxf(requested.size(), 1.0)
		_say(
			_step("load", share),
			"Loading the lot (%d of %d)" % [requested.size() - waiting.size(), requested.size()]
		)
		await get_tree().process_frame
	_finish("load")


func _load_sounds() -> void:
	var ids := SoundCatalog.ids()
	var at := 0
	while at < ids.size():
		var until := Time.get_ticks_msec() + SOUND_BUDGET_MSEC
		while at < ids.size() and Time.get_ticks_msec() < until:
			Audio.preload_sound(ids[at])
			at += 1
		_say(_step("sounds", float(at) / ids.size()), "Tuning the speakers")
		await get_tree().process_frame
	_finish("sounds")


## The lot from high above, every lamp lit and then every lamp dark.
func _lot_pass() -> void:
	var lot := _night.world.greybox
	var bounds := _bounds_of(lot)
	lot_bounds = bounds
	var centre := bounds.get_center()
	var height := maxf(bounds.size.x, bounds.size.z) * 0.75 + 30.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = 90.0
	_camera.far = height * 4.0
	_camera.look_at_from_position(
		Vector3(centre.x, height, centre.z), Vector3(centre.x, 0.0, centre.z), Vector3.FORWARD
	)
	_say(_step("lot", 0.0), "Lighting the lot")
	await _shots(_night)
	_say(_step("lot", 0.5), "Putting the lights out")
	var lights: Array[Light3D] = []
	var was: Array[bool] = []
	for node in lot.find_children("*", "Light3D", true, false):
		lights.append(node as Light3D)
		was.append((node as Light3D).visible)
		(node as Light3D).visible = false
	await _shots(_night)
	for i in lights.size():
		lights[i].visible = was[i]
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = SHOT_FOV
	_finish("lot")


## Everything that comes and goes in a night, under each light condition.
func _stage_pass() -> void:
	_stage = Node3D.new()
	_stage.name = "WarmupStage"
	_stage.position = Vector3(0.0, STAGE_HEIGHT, 0.0)
	_night.add_child(_stage)
	for i in LIGHT_CELLS.size():
		var cell: Dictionary = LIGHT_CELLS[i]
		_say(_step("stage", float(i) / LIGHT_CELLS.size()), "Setting the scene: %s" % cell["label"])
		var rig := _light_rig(cell)
		var props := _stage_row()
		_show_crane()
		await _shot_at(NEAR_SHOT)
		await _shot_at(FAR_SHOT)
		_say(_step("stage", (i + 0.5) / LIGHT_CELLS.size()), "Firing: %s" % cell["label"])
		_replay_effects()
		await _shot_at(NEAR_SHOT)
		_keep_materials(_night.view)
		# The next condition starts clean: a flash left over would put an omni light on it.
		_night.view.effects.stop_all()
		for effect in _night.view.effects.get_children():
			if not _night.view.effects.owns(effect):
				effect.free()
		_hide_crane()
		props.free()
		rig.free()
		await get_tree().process_frame
	_finish("stage")


## The prize crane on the stage in the state that shows the most: its dud, its sparks and its beam
## (it stands out of sight until the night's first frame puts it on its spot).
func _show_crane() -> void:
	var crane := _night.view.crane.crane if _night.view.crane != null else null
	if crane == null:
		return
	crane.visible = true
	crane.global_position = _stage.global_position + Vector3(6.0, 0.0, -6.0)
	crane.show_state({"stage": CraneState.Stage.LEAVING, "left": 1.0, "spot": 0}, 0.0)


func _hide_crane() -> void:
	var crane := _night.view.crane.crane if _night.view.crane != null else null
	if crane == null:
		return
	crane.show_state({"stage": CraneState.Stage.READY, "left": 0.0, "spot": 0}, 0.0)
	crane.visible = false


func _light_rig(cell: Dictionary) -> Node3D:
	var rig := Node3D.new()
	_stage.add_child(rig)
	if cell["omni"]:
		var omni := OmniLight3D.new()
		omni.omni_range = 18.0
		omni.position = Vector3(0.0, 4.0, 2.0)
		rig.add_child(omni)
	if cell["spot"]:
		var spot := SpotLight3D.new()
		spot.spot_range = 24.0
		spot.spot_angle = 70.0
		rig.add_child(spot)
		spot.look_at_from_position(Vector3(0.0, 7.0, 6.0), Vector3(0.0, 0.0, -1.0))
	return rig


## A row of every zombie look, then the scenes the weapons and grenades bring, in front of it.
func _stage_row() -> Node3D:
	var row := Node3D.new()
	_stage.add_child(row)
	var looks := ZombieModels.VARIANTS
	for i in looks.size():
		var look: StringName = looks[i]
		var view := ZombieView.new()
		row.add_child(view)
		view.setup(ZombieModels.scene(look), i, 0.0, 0.7, look)
		(
			view
			. apply(
				{
					"position": Vector3((i - (looks.size() - 1) / 2.0) * ROW_SPACING, 0.0, -2.0),
					"yaw": 0.0,
					"mode": ZombieBody.Mode.CHASE,
					"tearing": false,
					"episode": 0,
					"speed": 1.0,
					"look": look,
				},
				0.0
			)
		)
		view.advance_animation()
	var at := 0
	for path in WarmupManifest.drawable_dependencies(WarmupManifest.definition_paths()):
		var item := _instance_of(path)
		if item != null:
			row.add_child(item)
			item.position = Vector3(-6.0 + at * 1.2, 1.0, 1.5)
			at += 1
	return row


func _instance_of(path: String) -> Node3D:
	var resource := load(path)
	if resource is PackedScene:
		return (resource as PackedScene).instantiate() as Node3D
	if resource is Mesh:
		var instance := MeshInstance3D.new()
		instance.mesh = resource
		return instance
	return null


## One of each thing the view draws for an event, from a sample event of each kind.
func _replay_effects() -> void:
	var view := _night.view
	var at := _stage.global_position + Vector3(-3.0, 1.4, 1.5)
	var weapons := WeaponCatalog.all()
	for i in weapons.size():
		var def := weapons[i]
		var muzzle := at + Vector3(i * 1.1, 0.0, 0.0)
		var ends: Array[Vector3] = []
		for _p in maxi(def.pellets, 1):
			ends.append(muzzle + Vector3(0.0, -0.3, -3.5))
		# No shooter (no body to hang the flash on). Every other weapon's shots land on a zombie, the
		# rest on a wall: the flash, the impact on a wall and the one on flesh are all drawn.
		var flesh: Array[Vector3] = []
		if i % 2 == 0:
			flesh.append_array(ends)
		(
			view
			. draw_event(
				{
					"type": &"shot_fired",
					"weapon_id": def.id,
					"shooter_id": -1,
					"muzzle": muzzle,
					"ends": ends,
					"flesh": flesh,
				}
			)
		)
	(
		view
		. draw_event(
			{
				"type": &"damage_dealt",
				"point": at + Vector3(0.0, 0.5, -2.0),
				"damage": float(DIGITS_NUMBER),
				"headshot": false,
			}
		)
	)
	(
		view
		. draw_event(
			{
				"type": &"damage_dealt",
				"point": at + Vector3(1.0, 0.5, -2.0),
				"damage": float(DIGITS_NUMBER),
				"headshot": true,
			}
		)
	)
	view.draw_event({"type": &"projectile_burst", "point": at + Vector3(2.0, 0.0, -2.0)})
	for def_path in _grenade_defs():
		var blast := BlastEffect.new()
		view.effects.add_child(blast)
		blast.play(at + Vector3(3.0, -1.0, -2.0), load(def_path) as GrenadeDef)
		blast.gibs(at, Vector3.UP, 1)


func _grenade_defs() -> Array[String]:
	var paths: Array[String] = []
	for path in WarmupManifest.definition_paths():
		if path.begins_with(WarmupManifest.GRENADE_DEFS):
			paths.append(path)
	return paths


## Keeps every material under `root` alive for the night.
func _keep_materials(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.material_override != null:
			_pins.append(geometry.material_override)
		if geometry.material_overlay != null:
			_pins.append(geometry.material_overlay)
		if geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
			var mesh := (geometry as MeshInstance3D).mesh
			_pins.append(mesh)
			if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material != null:
				_pins.append((mesh as PrimitiveMesh).material)
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material != null:
					_pins.append(material)


## The camera looks at the middle of the row from `distance`, and the frames are held.
func _shot_at(distance: float) -> void:
	var middle := _stage.global_position + Vector3(0.0, 1.5, 0.0)
	_camera.look_at_from_position(middle + Vector3(0.0, 1.5, distance), middle)
	await _shots(_night)


## Waits for `SHOT_FRAMES` frames to be drawn and records what the tree held in them.
func _shots(root: Node) -> void:
	for _i in SHOT_FRAMES:
		await get_tree().process_frame
		# A headless run draws nothing and never says a frame was drawn.
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		ledger.record(root)
		shots += 1


func _bounds_of(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var box := geometry.global_transform * geometry.get_aabb()
		if box.size.length() > 400.0:  # the ground that stretches past the lot
			continue
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _mute() -> Dictionary[StringName, bool]:
	var before: Dictionary[StringName, bool] = {}
	for bus in BUSES_MUTED:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			before[bus] = AudioServer.is_bus_mute(index)
			AudioServer.set_bus_mute(index, true)
	return before


func _unmute(before: Dictionary[StringName, bool]) -> void:
	for bus in before:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), before[bus])


## The bar's fraction when `share` (0 to 1) of `step` is done.
func _step(step: String, share: float) -> float:
	return _done + float(WEIGHTS[step]) * clampf(share, 0.0, 1.0)


func _finish(step: String) -> void:
	_done += float(WEIGHTS[step])
	_say(_done, "")


func _say(fraction: float, text: String) -> void:
	progress.emit(fraction, text)
