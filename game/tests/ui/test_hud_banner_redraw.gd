# The banner's bulbs are polygons the Compatibility renderer builds into buffers of their own: the
# board is drawn when the chase steps on, not every frame (#834).
extends GdUnitTestSuite


func test_the_banner_is_redrawn_when_the_bulbs_step_not_every_frame() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var fixture := HudFixture.make(host, 1)
	var banner := fixture.hud.banner
	banner.show_banner("ROUND 3", "", HudBanner.Rank.ROUND)
	# Past the pop-in, whose changing scale makes the engine redraw the board itself.
	fixture.advance(HudTuning.current().banner_in + 0.1)
	await get_tree().process_frame
	var draws := [0]
	banner.draw.connect(func() -> void: draws[0] += 1)
	# A second of 60 Hz frames (the banner also advances itself, so up to two seconds of chase):
	# about ten steps, a draw each, not sixty.
	for i in 60:
		banner.advance(1.0 / 60.0)
		await get_tree().process_frame
	assert_int(draws[0]).is_between(1, 2 * int(HudBanner.CHASE) + 3)
