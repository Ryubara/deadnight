extends GdUnitTestSuite
## The dead's voices through a real night: the server's frames and events reach `ZombieVoices` in
## the view, and what a zombie does on the lot is what is requested. No wall time: ticks are
## run by hand.


func after_test() -> void:
	Audio.listener = null


func test_the_headliner_roars_when_it_rises_on_the_lot() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL, NightFixture.boss_tuning())
	var id := NightFixture.first_of_type(night, &"headliner")
	assert_int(id).is_greater(0)
	NightFixture.run(night, 5)
	assert_int(int(night.view.voices.requested.get(&"zombie_roar", 0))).is_equal(1)
	await NightFixture.settle_bake(night)


func test_a_walker_at_the_player_snarls_swings_and_is_heard_hurt() -> void:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, NightFixture.only_tuning(&"walker")
	)
	Audio.listener = night.player()  # the manual night films from above; the ears are the player's
	var id := NightFixture.first_of_type(night, &"walker")
	var body: ZombieBody = night.server.sim.zombies[id]
	var requested: Dictionary = night.view.voices.requested
	var started: int = Audio.started
	# Hold it a metre and a half from the player until its blow has landed.
	for _i in 400:
		body.position = night.state.position() + Vector3(0.0, 0.0, 1.5)
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 1)
		if requested.has(&"zombie_grunt"):
			break
	assert_bool(requested.has(&"zombie_alert")).is_true()
	assert_bool(requested.has(&"zombie_grunt")).is_true()
	assert_int(Audio.started).is_greater(started)
	night.server.rules.apply(RulesAction.skip_break())
	var held := body.position
	var shot := NightFixture.shoot_at(night, held)
	# Held where it was shot at: the player stands above the floor here, and a zombie lets itself
	# down to the floor its path runs on.
	for _i in 30:
		body.position = held
		NightFixture.run(night, 1, shot)
	assert_bool(requested.has(&"zombie_hurt") or requested.has(&"zombie_death")).is_true()
	await NightFixture.settle_bake(night)
