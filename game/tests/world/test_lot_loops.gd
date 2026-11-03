# The lot's loops for kiting (docs/design/map.md, "Loops for kiting"): a loop under about 40 m
# is too short for a pack to string out. Each loop here is walked along the dead's own walking
# mesh (an agent of the dead's radius, every door sold), through waypoints set round the things
# it circles, so its length is the way a pack follows, not a guess from the plan. The loops of
# the thin stretches (#855) are the wreck rows on the field's flanks, the kerb walls of its south
# strip, the cartons and container B in the yard's east third, and the carton rows and the booths
# in the ticket plaza.
extends GdUnitTestSuite

## The dead's agent radius (`NavmeshBaker.AGENT_RADIUS`).
const DEAD_RADIUS := 0.5
## A waypoint counts as reached when the way ends this close to it.
const REACHED := 0.3
## [name, the least length in metres, waypoints (x, z) in order round the loop]. The waypoints
## hug the outside corners of what the loop circles (0.6 to 0.8 m off; the walking mesh's edge is
## 0.5 m off), so the length is the shortest lap, the one a pack cuts to.
const LOOPS := [
	[
		"field west flank: round the wreck row",
		40.0,
		[
			Vector2(-53.7, -26.0),
			Vector2(-50.3, -26.0),
			Vector2(-50.3, -7.5),
			Vector2(-53.7, -7.5),
		],
	],
	[
		"field east flank: round the wreck row",
		40.0,
		[
			Vector2(51.8, -25.2),
			Vector2(55.2, -25.2),
			Vector2(55.2, -6.6),
			Vector2(51.8, -6.6),
		],
	],
	[
		"field south strip, west: round the kerb walls",
		40.0,
		[
			Vector2(-38.2, -9.9),
			Vector2(-17.8, -9.9),
			Vector2(-17.8, -8.1),
			Vector2(-38.2, -8.1),
		],
	],
	[
		"field south strip, east: round the kerb walls",
		40.0,
		[
			Vector2(18.1, -10.9),
			Vector2(38.2, -10.9),
			Vector2(38.2, -9.1),
			Vector2(18.1, -9.1),
		],
	],
	[
		"yard east third: round the cartons and container B",
		40.0,
		[
			Vector2(57.4, 13.9),
			Vector2(58.5, 14.4),
			Vector2(58.5, 25.3),
			Vector2(55.8, 28.8),
			Vector2(49.2, 28.8),
			Vector2(49.2, 25.8),
		],
	],
	[
		"plaza: round the booths",
		40.0,
		[
			Vector2(-9.4, 40.2),
			Vector2(9.4, 40.2),
			Vector2(9.4, 47.0),
			Vector2(-9.4, 47.0),
		],
	],
	[
		"plaza: round the carton rows",
		25.0,
		[
			Vector2(-6.4, 50.5),
			Vector2(6.4, 50.5),
			Vector2(6.4, 52.7),
			Vector2(-6.4, 52.7),
		],
	],
	[
		"plaza: round the booths and the carton rows",
		40.0,
		[
			Vector2(-9.4, 40.2),
			Vector2(9.4, 40.2),
			Vector2(9.4, 47.0),
			Vector2(6.4, 50.5),
			Vector2(6.4, 52.7),
			Vector2(-6.4, 52.7),
			Vector2(-6.4, 50.5),
			Vector2(-9.4, 47.0),
		],
	],
]


func test_every_loop_is_long_enough_for_a_pack() -> void:
	var lot := await LotFixture.make_lot(self, LotFixture.door_table().keys())
	auto_free(lot.get_parent())
	var nav := LotNavigation.new(lot, DEAD_RADIUS)
	await nav.settle(get_tree())
	var lengths: Array[String] = []
	for loop: Array in LOOPS:
		var points: Array = loop[2]
		var total := 0.0
		for i in points.size():
			var from := Vector3(points[i].x, 0.0, points[i].y)
			var to := Vector3(
				points[(i + 1) % points.size()].x, 0.0, points[(i + 1) % points.size()].y
			)
			var way := nav.path(from, to, true)
			(
				assert_bool(way.size() > 1)
				. override_failure_message("%s: no way at %s" % [loop[0], from])
				. is_true()
			)
			if way.size() < 2:
				continue
			var end := way[way.size() - 1]
			(
				assert_float(Vector2(end.x - to.x, end.z - to.z).length())
				. override_failure_message("%s: %s is not reached from %s" % [loop[0], to, from])
				. is_less_equal(REACHED)
			)
			for j in way.size() - 1:
				total += Vector2(way[j + 1].x - way[j].x, way[j + 1].z - way[j].z).length()
		lengths.append("%s %.1f m" % [loop[0], total])
		(
			assert_float(total)
			. override_failure_message("%s is %.1f m, under %.0f" % [loop[0], total, loop[1]])
			. is_greater_equal(loop[1])
		)
	print("LOOPS ", "; ".join(lengths))
