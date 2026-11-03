# The warm-up before a night: what it loads and draws, and that it draws all a night does.
extends GdUnitTestSuite

## Ticks of a night played by the bot after the warm-up (a minute of game time).
const PLAYED_TICKS := 3600
## Ticks between two looks at what the night draws.
const LOOK_EVERY := 30


func _warmed_night(tuning: RulesTuning = null) -> Night:
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, tuning)
	return night


## What the night draws while the bot plays, as the strings of `DrawLedger`, over `ticks` ticks.
func _drawn_while_playing(night: Night, ticks: int) -> Dictionary[String, int]:
	night.server.rules.apply(RulesAction.skip_break())
	var drawn: Dictionary[String, int] = {}
	for i in ticks:
		night.tick()
		if i % LOOK_EVERY == 0:
			drawn.merge(DrawLedger.strings_of(night))
	return drawn


func test_the_manifest_names_every_zombie_look_and_weapon() -> void:
	var paths := WarmupManifest.resource_paths()
	for look in ZombieModels.VARIANTS:
		assert_bool(paths.has(ZombieModels.path_of(look))).is_true()
	for id in WeaponCatalog.IDS:
		assert_bool(paths.has(WeaponCatalog.DIR + String(id) + ".tres")).is_true()
	assert_bool(paths.has("res://gameplay/grenades/defs/frag.tres")).is_true()
	assert_bool(paths.has(ZombieRig.EXTRA_CLIPS_FILE)).is_true()


func test_the_manifest_has_the_repair_hammer_and_its_model() -> void:
	var paths := WarmupManifest.resource_paths()
	assert_bool(paths.has(PlayerAnimation.HAMMER_HOLD)).is_true()
	var hold := load(PlayerAnimation.HAMMER_HOLD) as WeaponHold
	assert_bool(paths.has(hold.scene)).is_true()
	var drawn := WarmupManifest.drawable_dependencies(WarmupManifest.definition_paths())
	assert_bool(drawn.has(hold.scene)).is_true()


func test_the_manifest_follows_a_definition_to_its_scenes() -> void:
	# A definition that points at a model brings the model: dependencies are read, not listed.
	var dependencies := WarmupManifest.dependencies_of("res://gameplay/weapons/defs/pistol.tres")
	assert_bool(dependencies.has("res://gameplay/weapons/weapon_def.gd")).is_true()


func test_the_warm_up_holds_what_it_loaded_and_the_sounds() -> void:
	var night := await _warmed_night()
	var pinned := night.warmup.pinned_paths()
	for look in ZombieModels.VARIANTS:
		assert_bool(pinned.has(ZombieModels.path_of(look))).is_true()
	for id: StringName in SoundCatalog.ids():
		# 0 files left to load: every variant of every sound is already in the service's cache, except
		# the deferred sounds' (their weapons' and voices'), which wait in the decode line.
		if SoundCatalog.get_def(id).deferred:
			continue
		assert_int(Audio.preload_sound(id)).is_equal(0)
	assert_int(night.warmup.shots).is_greater(20)
	night.queue_free()


func test_the_night_is_not_running_until_the_warm_up_is_done() -> void:
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	var fractions: Array[float] = []
	night.loading.connect(func(fraction: float, _text: String) -> void: fractions.append(fraction))
	await night.start(Night.Mode.MANUAL, 7)
	assert_bool(night.running).is_true()
	assert_float(fractions[0]).is_equal(0.0)
	assert_float(fractions[-1]).is_equal(1.0)
	var sorted := fractions.duplicate()
	sorted.sort()
	assert_array(fractions).is_equal(sorted)
	night.queue_free()


func test_the_warm_up_leaves_the_players_camera_current_and_the_lamps_as_they_were() -> void:
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	await night.start(Night.Mode.HUMAN, 7)
	assert_object(get_viewport().get_camera_3d()).is_same(night.player().camera_rig.camera())
	var lit := 0
	for lamp in night.view.lamps.lamps:
		if lamp.light.visible:
			lit += 1
	assert_int(lit).is_greater(0)
	night.queue_free()


func test_a_night_draws_nothing_the_warm_up_did_not() -> void:
	var night := await _warmed_night(NightFixture.boss_tuning())
	var drawn := await _drawn_while_playing(night, PLAYED_TICKS)
	var absent := night.warmup.ledger.missing(drawn)
	(
		assert_array(absent)
		. override_failure_message(
			(
				"The night drew these and the warm-up did not (add them to `NightWarmup`'s stage):\n%s"
				% "\n".join(absent)
			)
		)
		. is_empty()
	)
	night.queue_free()


func test_a_first_flare_shot_draws_nothing_the_warm_up_did_not() -> void:
	# The shot of the flare gun as the server tells it (#483: its first shot hitched): the muzzle
	# flash, the flare in the air, where it lands and the fire that calls the dead.
	var night := await _warmed_night()
	var muzzle := night.player().global_position + Vector3(0.0, 1.5, -0.5)
	var landing := muzzle + Vector3(0.0, -1.2, -9.0)
	(
		night
		. view
		. draw_event(
			{
				"type": &"shot_fired",
				"weapon_id": &"flare_gun",
				"muzzle": muzzle,
				"ends": [muzzle + Vector3(0.0, 0.0, -3.0)],
				"flesh": [],
			}
		)
	)
	(
		night
		. view
		. draw_event(
			{
				"type": &"projectile_spawned",
				"projectile_id": 7,
				"shooter_id": 1,
				"weapon_id": &"flare_gun",
				"position": muzzle,
				"velocity": Vector3(0.0, 2.0, -12.0),
			}
		)
	)
	assert_int(night.view.projectiles_in_flight()).is_equal(1)
	var drawn := DrawLedger.strings_of(night)
	night.view.draw_event({"type": &"projectile_burst", "projectile_id": 7, "point": landing})
	night.view.draw_event({"type": &"lure_started", "point": landing, "seconds": 8.0})
	await get_tree().process_frame
	drawn.merge(DrawLedger.strings_of(night))
	var absent := night.warmup.ledger.missing(drawn)
	(
		assert_array(absent)
		. override_failure_message(
			"The flare's first shot drew these and the warm-up did not:\n%s" % "\n".join(absent)
		)
		. is_empty()
	)
	night.queue_free()


func test_the_warm_up_draws_the_crane_in_every_stage_and_keeps_its_materials() -> void:
	# The night's own crane is hidden until the server's first frame, so the warm-up draws a copy:
	# whatever the real one is made of (cabinet, glass, beam, sparks) is in the ledger.
	var night := await _warmed_night()
	var crane_strings := DrawLedger.strings_of(night.view.crane.crane)
	assert_int(crane_strings.size()).is_greater(3)
	assert_array(night.warmup.ledger.missing(crane_strings)).is_empty()
	night.queue_free()


func test_the_check_notices_a_material_the_warm_up_never_drew() -> void:
	# The check above must be able to fail: a new effect with a material of its own is reported.
	var night := await _warmed_night()
	var effect := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.no_depth_test = true
	effect.mesh = QuadMesh.new()
	effect.material_override = material
	night.view.add_child(effect)
	var absent := night.warmup.ledger.missing(DrawLedger.strings_of(night))
	assert_int(absent.size()).is_equal(1)
	assert_str(absent[0]).starts_with("mesh|standard:")
	night.queue_free()


func test_the_lot_is_drawn_in_pieces_and_nothing_is_left_out_of_the_picture() -> void:
	var night := await _warmed_night()
	# A frame meets one new kind of material at most (`DrawReveal`): the lot is many steps, not one.
	assert_int(night.warmup.lot_steps).is_greater(8)
	assert_int(night.warmup.held_back()).is_equal(0)
	night.queue_free()


func test_the_warm_up_draws_the_flares_embers_and_keeps_their_programs() -> void:
	# A flare's lure is a particle system: its process material and the material of its quad are
	# programs of their own, built when the system first runs and freed with the last material that
	# uses them. The sample lure used to be gone (it expired by the frame times of the warm-up, which
	# take seconds in a browser) before its first draw, so the first real flare built them: 10
	# programs and a frame of 0.3 to 1.8 s in Chrome (#502).
	var night := await _warmed_night()
	var seen := night.warmup.ledger.seen.keys().filter(
		func(string: String) -> bool: return string.begins_with("particles")
	)
	(
		assert_array(seen)
		. override_failure_message("the warm-up drew no particle system")
		. is_not_empty()
	)
	assert_int(night.warmup.pinned_count(&"ParticleProcessMaterial")).is_greater(0)
	assert_int(night.warmup.pinned_count(&"StandardMaterial3D")).is_greater(0)
	# The sample is freed by hand, not left burning in the night.
	assert_array(night.view.find_children("*", "LureView", true, false)).is_empty()
	night.queue_free()


func test_the_check_notices_a_particle_system_the_warm_up_never_drew() -> void:
	var night := await _warmed_night()
	var particles := GPUParticles3D.new()
	var process := ParticleProcessMaterial.new()
	process.turbulence_enabled = true
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particles.process_material = process
	particles.draw_pass_1 = QuadMesh.new()
	night.view.add_child(particles)
	var absent := night.warmup.ledger.missing(DrawLedger.strings_of(night))
	assert_array(absent).contains(["particles|" + DrawLedger.process_key(process)])
	night.queue_free()
