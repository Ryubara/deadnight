extends GdUnitTestSuite
## A dead one in a pocket of the lot's walking mesh finds its way back (the nightly soak, #770): the
## strip behind the screen has stretches the walking mesh does not join to the field, a zombie the
## crowd shoves into one stands at the end of a path that goes nowhere, and the round it belongs to
## never ends. In the real lot, on the real mesh.

const STEP := Night.STEP
## A place in the pocket the soak found a walker standing in for eight minutes, and the person it
## chased.
const POCKET := Vector3(4.0, -0.5, -52.8)
const PERSON := Vector3(4.0, 0.1, -38.1)


func test_a_zombie_in_a_pocket_of_the_mesh_is_put_back_and_reaches_the_person() -> void:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), 5)
	night.gather()
	night.server.body_of(1).teleport(PERSON)
	night.server.rules.apply(RulesAction.skip_break())
	var zombie := night.drop_zombie(POCKET, 4.0)
	assert_object(zombie).is_not_null()
	# The mesh really has no way out of the pocket (the premise of the test).
	var way := NavigationServer3D.map_get_path(night.world.map(), POCKET, PERSON, true)
	(
		assert_float(
			Vector2(way[way.size() - 1].x - PERSON.x, way[way.size() - 1].z - PERSON.z).length()
		)
		. is_greater(ZombieSim.STRAND_GAP)
	)
	var nearest := INF
	for _i in 70 * 60:
		night.tick()
		nearest = minf(
			nearest, Vector2(zombie.position.x - PERSON.x, zombie.position.z - PERSON.z).length()
		)
		if nearest < 3.0:
			break
	assert_int(night.server.director.relocated).is_greater_equal(1)
	assert_float(nearest).is_less(3.0)
	night.dispose()
