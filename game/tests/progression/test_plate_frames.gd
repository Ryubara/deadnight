extends GdUnitTestSuite
## The plate frames (#1071): each frame the ladder gives comes at its level, a frame a challenge
## gives comes once and from a stat the night counts, one is worn at a time and held to what the
## player owns, and the art of every frame composes round a ticket, a row and a swatch.

const DAY := 20401

var _plates: PlateCatalog
var _challenges: ChallengeCatalog


func before_test() -> void:
	_plates = PlateCatalog.shipped()
	_challenges = ChallengeCatalog.load_default()


func _done(...ids: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: Variant in ids:
		found.append(StringName(str(id)))
	return found


func test_each_level_frame_unlocks_at_its_level_and_not_a_level_before() -> void:
	for entry: Array in [[&"chrome", 29], [&"brass", 37], [&"neon", 50], [&"gold", 55]]:
		var frame: StringName = entry[0]
		var level: int = entry[1]
		assert_int(int(_plates.source(PlateCatalog.FRAME, frame)["level"])).is_equal(level)
		assert_bool(_plates.owns(PlateCatalog.FRAME, frame, level - 1, _done())).is_false()
		assert_bool(_plates.owns(PlateCatalog.FRAME, frame, level, _done())).is_true()
		assert_str(_plates.how_to_get(PlateCatalog.FRAME, frame)).is_equal("Reach level %d" % level)
	assert_array(_plates.owned(PlateCatalog.FRAME, 55, _done())).contains_exactly(
		[&"chrome", &"brass", &"neon", &"gold"]
	)
	# The ladder's rows are told about now that their art is drawn.
	var rows := 0
	for row: Dictionary in LadderUnlocks.shipped().earned_at(29):
		rows += 1 if row["slot"] == &"plate_frame" else 0
	assert_int(rows).is_equal(1)


func test_a_challenge_frame_is_granted_once_when_the_challenge_is_done() -> void:
	var owner := _challenges.giver_of(PlateCatalog.FRAME, &"filmstrip")
	assert_str(owner.id).is_equal("f_filmstrip")
	assert_bool(_plates.owns(PlateCatalog.FRAME, &"filmstrip", 55, _done())).is_false()
	assert_bool(_plates.owns(PlateCatalog.FRAME, &"filmstrip", 1, _done("f_filmstrip"))).is_true()
	# The night finishes it once: reaching round 20 finishes it, going further moves nothing.
	var profile := ChallengeProfile.fresh(5)
	profile.refresh(_challenges, DAY)
	var finished := 0
	for round_reached in [19, 20, 21]:
		for advance in profile.apply(_challenges, ChallengeStats.ROUND, round_reached, 1):
			if advance["id"] == "f_filmstrip" and advance["completed"]:
				finished += 1
	assert_int(finished).is_equal(1)
	# And it lands on the profile once, however many times it is told.
	var saved := Profile.new()
	saved.mark_done(&"f_filmstrip")
	saved.mark_done(&"f_filmstrip")
	assert_array(saved.done).contains_exactly([&"f_filmstrip"])


func test_no_frame_is_given_by_a_challenge_the_night_cannot_count() -> void:
	var seen := 0
	for grant in _challenges.grants():
		if grant["kind"] != PlateCatalog.FRAME:
			continue
		seen += 1
		var def: ChallengeDef = grant["def"]
		assert_bool(_plates.has(PlateCatalog.FRAME, grant["id"])).is_true()
		var stats: Array[StringName] = def.stats.duplicate()
		if stats.is_empty():
			stats.append(def.stat)
		for stat in stats:
			(
				assert_bool(ChallengeStats.FIXED.has(stat))
				. override_failure_message(
					"%s asks for %s, which the night does not count" % [def.id, stat]
				)
				. is_true()
			)
	assert_int(seen).is_equal(3)
	assert_array(_plates.problems()).is_empty()


func test_one_frame_is_worn_at_a_time_and_only_one_that_is_owned() -> void:
	var worn := _plates.worn({"frame": "brass"}, 40, _done())
	assert_str(worn["frame"]).is_equal("brass")
	# Below its level, or with the challenge not done, it is nothing.
	assert_str(_plates.worn({"frame": "brass"}, 36, _done())["frame"]).is_equal("")
	assert_str(_plates.worn({"frame": "velvet_rope"}, 55, _done())["frame"]).is_equal("")
	assert_str(_plates.worn({"frame": "velvet_rope"}, 1, _done("f_velvet_rope"))["frame"]).is_equal(
		"velvet_rope"
	)
	# An id nobody has, or one of another kind, is nothing.
	assert_str(_plates.worn({"frame": "dead_eye"}, 55, _done("f_dead_eye"))["frame"]).is_equal("")
	assert_str(_plates.worn({"frame": 7}, 55, _done())["frame"]).is_equal("")


func test_equipping_a_frame_writes_it_to_the_profile_and_changing_it_replaces_it() -> void:
	var path := "user://test_plate_frames_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var store := ProfileStore.open(path, func() -> bool: return true)
	assert_bool(store.equip(&"frame", &"chrome")).is_true()
	assert_bool(store.equip(&"frame", &"chrome")).is_false()
	assert_bool(store.equip(&"frame", &"neon")).is_true()
	assert_str(store.profile.chosen(&"frame")).is_equal("neon")
	assert_bool(store.equip(&"frame", &"")).is_true()
	assert_str(store.profile.chosen(&"frame")).is_equal("")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_every_frame_composes_round_a_ticket_a_row_and_a_swatch() -> void:
	var ticket := HudStyle.ticket_points(Rect2(0, 0, 330, 66), HudStyle.NOTCH * 0.6)
	var row := PlateFrames.rect_outline(Rect2(0, 0, 900, 46))
	for id in _plates.ids(PlateCatalog.FRAME):
		var piece := _plates.piece(PlateCatalog.FRAME, id)
		for outline: PackedVector2Array in [ticket, row]:
			var ops := PlateFrames.build(
				StringName(piece["style"]), StringName(piece["palette"]), outline, 3.0
			)
			assert_bool(ops.is_empty()).override_failure_message("%s draws nothing" % id).is_false()
			# The border stays inside the outline (the glow's halo is the deepest).
			var bounds := Rect2(outline[0], Vector2.ZERO)
			for point in outline:
				bounds = bounds.expand(point)
			for op in ops:
				for point in op["p"] as PackedVector2Array:
					assert_bool(bounds.grow(1.0).has_point(point)).is_true()


func test_a_frame_art_follows_its_outline_and_a_bare_one_draws_nothing() -> void:
	var art := FrameArt.make(&"gold", Vector2(300, 60))
	assert_int(art.op_count()).is_greater(0)
	art.frame_id = &""
	assert_int(art.op_count()).is_equal(0)
	art.frame_id = &"nonsense"
	assert_int(art.op_count()).is_equal(0)
	art.free()


func test_the_stroke_follows_the_height_between_two_and_five() -> void:
	assert_float(PlateFrames.width_for(20.0)).is_equal(2.0)
	assert_float(PlateFrames.width_for(32.0)).is_equal(2.0)
	assert_float(PlateFrames.width_for(46.0)).is_equal(3.0)
	assert_float(PlateFrames.width_for(48.0)).is_equal(4.0)
	assert_float(PlateFrames.width_for(66.0)).is_equal(5.0)
	assert_float(PlateFrames.width_for(200.0)).is_equal(5.0)
