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
##      programs of a mesh differ with the lights that reach it, and the generator can fail). The
##      lot is held out of the picture first and brought in a kind of material at a time
##      (`DrawReveal`), because the renderer's first draw of one shader takes about a second in a
##      browser and the lot has nine: all at once they were one 9 to 12 s frame;
##   4. on a stage high above the lot, in each of four light conditions (the moon alone, an omni
##      light, a spot light, both): every zombie look near and far, every weapon's and grenade's
##      scene, the repair hammer, the prize crane in each of its stages, and the night view's own
##      effects, replayed from sample events (a shot of each weapon, damage numbers with every
##      digit, a blast; the first light condition brings its props in the same way), and keeps
##      the materials those effects made, so the shaders they own are not freed with the
##      short-lived nodes (a shader goes with the last material that uses it, and would be built
##      again at every shot).
## The night's lights, environment and fog are used as they are: the stage is in the same world,
## seen through a camera of its own that is current for the warm-up.

## Fraction (0 to 1) done and what is being done.
signal progress(fraction: float, text: String)

## How long the warm-up's sample flare burns (s): long enough to be drawn, then it frees itself.
const WARMUP_LURE_SECONDS := 0.2
## The id of the sample flare the warm-up draws (a real shot never has it).
const WARMUP_PROJECTILE := -1
## The stage is this high above the lot, out of reach of every lamp.
const STAGE_HEIGHT := 150.0
## How far the zombies in a row stand apart.
const ROW_SPACING := 1.9
## Camera distances for the near shot (the near meshes) and the far one (past
## `ZombieModels.FAR_FROM`).
const NEAR_SHOT := 9.0
const FAR_SHOT := 34.0
const SHOT_FOV := 75.0
## How far behind the row of zombies the stage crane stands.
const CRANE_BEHIND := -6.0
## The light conditions every thing is drawn under: whether an omni and a spot light reach it.
const LIGHT_CELLS: Array[Dictionary] = [
	{"label": "moonlight", "omni": false, "spot": false},
	{"label": "an omni light", "omni": true, "spot": false},
	{"label": "a spot light", "omni": false, "spot": true},
	{"label": "both", "omni": true, "spot": true},
]
## Share of the bar each step takes.
## It follows the time each takes in a browser, so the bar moves at an even pace.
const WEIGHTS := {"load": 0.04, "sounds": 0.04, "lot": 0.50, "stage": 0.42}
## Milliseconds a frame may spend loading sounds, so the bar keeps moving.
const SOUND_BUDGET_MSEC := 8
## Frames each shot is held, so the draw reaches the screen (and the renderer builds what it needs).
const SHOT_FRAMES := 2
## Digits of the damage numbers: every glyph the numbers use is drawn once.
const DIGITS_NUMBER := 1234567890
const BUSES_MUTED: Array[StringName] = [&"Effects", &"Voice"]

## What was drawn: the warm-up records its tree after every shot.
var ledger := DrawLedger.new()
## Frames the warm-up drew, for tests.
var shots := 0
## The box around the lot that the lot pass looked at.
var lot_bounds := AABB()
## How many pieces the lot was brought in as (steps of `DrawReveal`), for tests.
var lot_steps := 0

var _night: Night
var _camera: Camera3D
var _before: Camera3D
## Everything the night will want again, held so it stays loaded (resources, effect materials).
var _pins: Array = []
var _stage: Node3D
var _done := 0.0
var _last_text := ""
## The night's drawn nodes, out of the picture until the lot pass brings them in.
var _held := DrawReveal.new()
## The viewports of their own (the HUD's portrait) that wait for the lot pass.
var _paused: Array[SubViewport] = []


## Runs every step; the night is not running meanwhile. The caller waits for it.
func run(night: Night) -> void:
	_night = night
	_before = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = SHOT_FOV
	add_child(_camera)
	# Nothing of the night is drawn until the lot pass brings it in, a kind of material at a time;
	# the HUD's portrait draws the Soldier with the same shaders, so it waits for them as well.
	_held.hide(night)
	_paused = _pause_viewports()
	_camera.make_current()
	var muted := _mute()
	await _load_resources()
	await _load_sounds()
	await _lot_pass()
	await _stage_pass()
	_unmute(muted)
	if is_instance_valid(_before):
		_before.make_current()
	_camera.queue_free()
	if _stage != null:
		_stage.queue_free()
	_say(1.0, "Ready")


## Stops the viewports of their own from drawing until `_resume_viewports`. A viewport that draws
## the Soldier (the HUD's portrait is drawn once, early) would meet its shaders all in one frame.
func _pause_viewports() -> Array[SubViewport]:
	var paused: Array[SubViewport] = []
	for node in get_tree().root.find_children("*", "SubViewport", true, false):
		var viewport := node as SubViewport
		RenderingServer.viewport_set_active(viewport.get_viewport_rid(), false)
		paused.append(viewport)
	return paused


func _resume_viewports() -> void:
	for viewport in _paused:
		if is_instance_valid(viewport):
			RenderingServer.viewport_set_active(viewport.get_viewport_rid(), true)
	_paused.clear()


## How many of the night's drawn nodes are still held out of the picture (none once it is done).
func held_back() -> int:
	return _held.pending()


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


## The lot from high above, brought in a kind of material at a time with every lamp lit, and then
## drawn with every lamp dark.
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
	var steps := _held.steps()
	lot_steps = steps.size()
	for i in steps.size():
		_say(
			_step("lot", 0.9 * float(i) / steps.size()),
			"Lighting the lot (%d of %d)" % [i + 1, steps.size()]
		)
		_held.reveal(steps[i])
		await _shots(_night, 1)
	_held.reveal_all()
	_resume_viewports()
	_say(_step("lot", 0.9), "Putting the lights out")
	# The lamps only: the moon is never switched off, so the programs without it are never used.
	var lights: Array[Light3D] = []
	var was: Array[bool] = []
	for node in lot.find_children("*", "Light3D", true, false):
		if node is DirectionalLight3D:
			continue
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
		var crane := _stage_crane()
		_show_crane(crane, CraneState.Stage.SPIN)
		if i == 0:
			await _bring_in(_stage, i, cell["label"])
		await _shot_at(NEAR_SHOT)
		_show_crane(crane, CraneState.Stage.GRAB)
		await _shot_at(FAR_SHOT)
		_show_crane(crane, CraneState.Stage.LEAVING)
		_say(_step("stage", (i + 0.5) / LIGHT_CELLS.size()), "Firing: %s" % cell["label"])
		_aim_at(NEAR_SHOT)
		await _replay_effects()
		await _shot_at(NEAR_SHOT)
		_keep_materials(_night.view)
		_keep_materials(crane)
		# The next condition starts clean: a flash left over would put an omni light on it.
		# The pooled impacts stay: they are the view's own, the rest is what the replay drew.
		for effect in _night.view.effects.get_children():
			if effect != _night.view.effects.impacts:
				effect.free()
		props.free()
		crane.free()
		rig.free()
		await get_tree().process_frame
	_finish("stage")


## Holds the stage's props out of the picture and brings them in a kind of material at a time, as
## the lot was: the first light condition meets every shader, the others only new programs.
func _bring_in(root: Node3D, cell_index: int, label: String) -> void:
	var held := DrawReveal.new()
	held.hide(root)
	_aim_at(NEAR_SHOT)
	var steps := held.steps()
	for i in steps.size():
		_say(
			_step("stage", (cell_index + 0.4 * float(i) / steps.size()) / LIGHT_CELLS.size()),
			"Setting the scene: %s (%d of %d)" % [label, i + 1, steps.size()]
		)
		held.reveal(steps[i])
		await _shots(_night, 1)
	held.reveal_all()


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


## A prize crane behind the row, a copy of the night's own (its cabinet, beam, light and sparks, a
## prize on its stage), since the night's is hidden until the server's first frame says where it
## stands.
func _stage_crane() -> PrizeCrane:
	var tuning := _night.rules_tuning
	var item := tuning.economy.item(&"crane_play")
	var crane := PrizeCrane.new()
	_stage.add_child(crane)
	crane.configure(tuning.crane, item.pool if item != null else [])
	crane.position = Vector3(0.0, 0.0, CRANE_BEHIND)
	return crane


## One frame of `stage` of the crane (every stage draws something the others do not: the cycling
## prize, the held one, the dud with its sparks and the failing beam).
func _show_crane(crane: PrizeCrane, stage: CraneState.Stage) -> void:
	var item := _night.rules_tuning.economy.item(&"crane_play")
	var weapon := item.pool[0] if item != null and not item.pool.is_empty() else &""
	crane.show_state({"stage": stage, "left": 1.0, "weapon": String(weapon)}, 0.1)


func _instance_of(path: String) -> Node3D:
	var resource := load(path)
	if resource is PackedScene:
		return (resource as PackedScene).instantiate() as Node3D
	if resource is Mesh:
		var instance := MeshInstance3D.new()
		instance.mesh = resource
		return instance
	return null


## One of each thing the view draws for an event, from a sample event of each kind. A frame is drawn
## after each weapon's shot and each kind of event, so a frame meets few new programs.
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
		(
			view
			. draw_event(
				{
					"type": &"shot_fired",
					"weapon_id": def.id,
					"muzzle": muzzle,
					"ends": ends,
					"flesh": [muzzle + Vector3(0.0, -0.3, -1.5)],
				}
			)
		)
		await _chunk()
	(
		view
		. draw_event(
			{
				"type": &"damage_dealt",
				"point": at + Vector3(0.0, 0.5, -2.0),
				"damage": float(DIGITS_NUMBER),
				"headshot": false,
				"melee": false,
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
				"melee": false,
			}
		)
	)
	await _chunk()
	var flare_at := at + Vector3(2.0, 0.0, -2.0)
	var flare := WeaponCatalog.get_def(&"flare_gun")
	(
		view
		. draw_event(
			{
				"type": &"projectile_spawned",
				"projectile_id": WARMUP_PROJECTILE,
				"shooter_id": -1,
				"weapon_id": flare.id,
				"position": flare_at,
				"velocity": Vector3.ZERO,
			}
		)
	)
	await _chunk()
	view.draw_event(
		{"type": &"projectile_burst", "projectile_id": WARMUP_PROJECTILE, "point": flare_at}
	)
	await _chunk()
	(
		view
		. draw_event(
			{
				"type": &"lure_started",
				"point": flare_at,
				"seconds": WARMUP_LURE_SECONDS,
			}
		)
	)
	await _chunk()
	for def_path in _grenade_defs():
		var blast := BlastEffect.new()
		view.effects.add_child(blast)
		blast.play(at + Vector3(3.0, -1.0, -2.0), load(def_path) as GrenadeDef)
		blast.gibs(at, Vector3.UP, 1)
		await _chunk()


## One frame of what was just made. The materials are kept first: an effect frees itself a fraction
## of a second after it starts, and a frame that builds programs can take longer than that.
func _chunk() -> void:
	_keep_materials(_night.view)
	await _shots(_night, 1)


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
	_aim_at(distance)
	await _shots(_night)


func _aim_at(distance: float) -> void:
	var middle := _stage.global_position + Vector3(0.0, 1.5, 0.0)
	_camera.look_at_from_position(middle + Vector3(0.0, 1.5, distance), middle)


## Waits for `frames` frames to be drawn and records what the tree held in them.
func _shots(root: Node, frames := SHOT_FRAMES) -> void:
	for _i in frames:
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
	if text != "" and text != _last_text:
		_last_text = text
		WebProbe.mark("warm-up: " + text)
	progress.emit(fraction, text)
