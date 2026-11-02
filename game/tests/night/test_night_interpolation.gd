# The night is drawn between physics ticks even though it hangs under a screen, which is a Control
# and, left alone, switches physics interpolation off for everything below it (issues #344, #353:
# the fix of #352 was measured in a test room under a plain Node and never reached the game).
extends GdUnitTestSuite


func test_a_night_under_a_screen_draws_its_bodies_between_ticks() -> void:
	var screen := auto_free(Control.new()) as Control
	add_child(screen)
	var night := await NightFixture.start(screen, Night.Mode.MANUAL)
	var player := night.player()
	assert_bool(player.is_physics_interpolated_and_enabled()).is_true()
	assert_bool(player.get_node(^"Model").is_physics_interpolated_and_enabled()).is_true()
	night.queue_free()


func test_the_camera_rig_is_still_left_to_its_own_blend() -> void:
	var screen := auto_free(Control.new()) as Control
	add_child(screen)
	var night := await NightFixture.start(screen, Night.Mode.MANUAL)
	assert_bool(night.player().camera_rig.is_physics_interpolated_and_enabled()).is_false()
	night.queue_free()


func test_the_other_players_are_drawn_from_their_own_track_not_blended_by_the_engine() -> void:
	var avatars := auto_free(RemoteAvatars.new()) as RemoteAvatars
	var screen := auto_free(Control.new()) as Control
	add_child(screen)
	screen.add_child(avatars)
	assert_bool(avatars.is_physics_interpolated_and_enabled()).is_false()
