extends GdUnitTestSuite
## Every breach is a window, never a door (#915): the dead climb in over its sill. The navigation
## mesh runs through the gap at the ground, so the climb is the simulation's own link: with the
## boards down a zombie is lifted to the sill's height over the wall and set down on the other
## side, slowed while it does, and drawn scrambling (the codec's climbing bit, the view's crawl
## clip and lean). At standing boards nobody climbs. A straight-line field: the wall is the line
## x = 0 and the way in is +x.

const GATE := &"win"
const SILL := 0.9
const THICK := 0.56
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}

var _barricades: BarricadeState


func before_test() -> void:
	_barricades = BarricadeState.new(BarricadeTuning.new())
	_barricades.boards[GATE] = 0


func _gate(sill: float = SILL, opening_half: float = 2.0) -> ZombieGate:
	return ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT, 2.05, sill, THICK, opening_half)


func _sim(sill: float = SILL) -> ZombieSim:
	var sim := ZombieFixture.sim()
	sim.gates[GATE] = _gate(sill)
	sim.barricades = _barricades
	return sim


func _walker(sim: ZombieSim, from_x: float, z: float = 0.0) -> ZombieBody:
	var zombie := sim.spawn(1, 2.0, Vector3(from_x, 0.0, z), 0.0, null, GATE)
	zombie.enter(ZombieBody.Mode.CHASE)
	return zombie


## Runs a zombie through the opening and returns what it did: its highest point, the x it
## reached it at, whether it ever climbed and its heights at the start and the end.
func _cross(sim: ZombieSim, zombie: ZombieBody, seconds: float) -> Dictionary:
	var out := {"max_y": 0.0, "at_x": 0.0, "climbed": false, "climb_seconds": 0.0}
	for _i in int(seconds / ZombieSim.STEP):
		sim.tick(ZombieSim.STEP, TARGETS)
		if zombie.position.y > out["max_y"]:
			out["max_y"] = zombie.position.y
			out["at_x"] = zombie.position.x
		if zombie.climbing:
			out["climbed"] = true
			out["climb_seconds"] += ZombieSim.STEP
	out["end_y"] = zombie.position.y
	out["end_x"] = zombie.position.x
	return out


func test_the_sill_lifts_in_the_wall_and_falls_off_on_both_ramps() -> void:
	var gate := _gate()
	var held := THICK * 0.5 + ZombieGate.BODY_CLEARANCE
	assert_float(gate.lift_at(Vector3(0.0, 0.0, 0.0))).is_equal_approx(SILL, 0.001)
	# A body's edge is on the sill's height as soon as it reaches the ledge.
	assert_float(gate.lift_at(Vector3(-held + 0.01, 0.0, 0.0))).is_equal_approx(SILL, 0.01)
	assert_float(gate.lift_at(Vector3(held - 0.01, 0.0, 0.0))).is_equal_approx(SILL, 0.01)
	var half_way := held + ZombieGate.CLIMB_RAMP * 0.5
	assert_float(gate.lift_at(Vector3(-half_way, 0.0, 0.0))).is_between(0.3, 0.6)
	assert_float(gate.lift_at(Vector3(half_way, 0.0, 0.0))).is_between(0.3, 0.6)
	var past := held + ZombieGate.CLIMB_RAMP + 0.01
	assert_float(gate.lift_at(Vector3(-past, 0.0, 0.0))).is_equal(0.0)
	assert_float(gate.lift_at(Vector3(past, 0.0, 0.0))).is_equal(0.0)


func test_a_zombie_in_the_wall_is_kept_between_the_jambs() -> void:
	var gate := ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT, 2.05, SILL, THICK, 0.8, 0.6)
	# The wall runs along z here (inward is +x): a body at z 0.5 in the wall, 0.6 clear half and 0.3
	# of body, is moved to 0.3; one in the room, or already clear, is left alone.
	var moved := gate.keep_in_opening(Vector3(0.0, 0.9, 0.5))
	var kept := 0.6 - ZombieGate.BODY_HALF_WIDTH - ZombieGate.JAMB_MARGIN
	assert_float(absf(moved.z)).is_equal_approx(kept, 0.001)
	assert_float(moved.x).is_equal(0.0)
	assert_vector(gate.keep_in_opening(Vector3(2.0, 0.0, 0.5))).is_equal(Vector3(2.0, 0.0, 0.5))
	assert_vector(gate.keep_in_opening(Vector3(0.0, 0.9, 0.1))).is_equal(Vector3(0.0, 0.9, 0.1))
	assert_vector(_gate().keep_in_opening(Vector3(0.0, 0.0, 1.5))).is_equal(Vector3(0.0, 0.0, 1.5))


func test_there_is_no_lift_beside_the_opening_or_where_there_is_no_sill() -> void:
	assert_float(_gate().lift_at(Vector3(0.0, 0.0, 2.5))).is_equal(0.0)
	assert_float(_gate(0.0).lift_at(Vector3.ZERO)).is_equal(0.0)
	assert_bool(_gate(0.0).climbs(Vector3.ZERO)).is_false()


func test_the_dead_climb_over_the_sill_and_come_down_inside() -> void:
	var sim := _sim()
	var zombie := _walker(sim, -6.0)
	var run := _cross(sim, zombie, 8.0)
	assert_bool(run["climbed"]).is_true()
	assert_float(run["max_y"]).is_equal_approx(SILL, 0.05)
	assert_float(run["at_x"]).is_between(-1.0, 1.0)
	assert_float(run["end_x"]).is_greater(3.0)
	assert_float(run["end_y"]).is_equal_approx(0.0, 0.01)
	assert_bool(zombie.climbing).is_false()


func test_a_gate_with_no_sill_leaves_the_dead_on_the_ground() -> void:
	var sim := _sim(0.0)
	var zombie := _walker(sim, -6.0)
	var run := _cross(sim, zombie, 8.0)
	assert_bool(run["climbed"]).is_false()
	assert_float(run["max_y"]).is_equal(0.0)


func test_at_standing_boards_nobody_climbs() -> void:
	_barricades.boards[GATE] = 3
	var sim := _sim()
	var zombie := _walker(sim, -3.0)
	var run := _cross(sim, zombie, 4.0)
	assert_bool(run["climbed"]).is_false()
	assert_float(run["max_y"]).is_equal(0.0)
	assert_float(zombie.position.x).is_less(0.0)


func test_a_zombie_walking_past_the_opening_does_not_climb() -> void:
	var sim := _sim()
	var zombie := _walker(sim, -6.0, 6.0)
	var run := _cross(sim, zombie, 4.0)
	assert_bool(run["climbed"]).is_false()
	assert_float(run["max_y"]).is_equal(0.0)


func test_the_climb_is_in_the_snapshot_and_a_dying_zombie_does_not_carry_it() -> void:
	var sim := _sim()
	var zombie := _walker(sim, 0.0)
	zombie.climbing = true
	var entries := ZombieCodec.decode(ZombieCodec.encode(sim.zombies))
	assert_bool(entries[0]["climbing"]).is_true()
	assert_int(entries[0]["mode"]).is_equal(ZombieBody.Mode.CHASE)
	assert_bool(entries[0]["tearing"]).is_false()
	zombie.climbing = false
	assert_bool(ZombieCodec.decode(ZombieCodec.encode(sim.zombies))[0]["climbing"]).is_false()
	zombie.climbing = true
	zombie.enter(ZombieBody.Mode.DYING)
	assert_bool(ZombieCodec.decode(ZombieCodec.encode(sim.zombies))[0]["climbing"]).is_false()
	assert_bool(zombie.view_entry()["climbing"]).is_false()


func test_the_view_scrambles_in_over_the_sill_and_stands_up_after() -> void:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.25, 0.7)
	var entry := {
		"id": 1,
		"position": Vector3(0, 0.5, 0),
		"yaw": 0.0,
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": 1.2,
		"climbing": true,
	}
	view.apply(entry, 0.033)
	view.apply(entry, 0.3)
	view.advance_animation()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	assert_bool(view.is_climbing()).is_true()
	assert_str(playback.get_current_node()).is_equal(ZombieRig.STATE_CRAWL)
	assert_float(view.model().rotation.x).is_equal_approx(deg_to_rad(ZombieView.CLIMB_LEAN), 0.001)
	entry["climbing"] = false
	view.apply(entry, 0.3)
	view.advance_animation()
	assert_bool(view.is_climbing()).is_false()
	assert_str(playback.get_current_node()).is_equal(ZombieRig.STATE_MOVE)
	assert_float(view.model().rotation.x).is_equal(0.0)


func test_a_zombie_swinging_at_the_sill_is_not_drawn_climbing() -> void:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.25, 0.7)
	(
		view
		. apply(
			{
				"id": 1,
				"position": Vector3.ZERO,
				"yaw": 0.0,
				"mode": ZombieBody.Mode.ATTACK,
				"episode": 2,
				"speed": 0.0,
				"climbing": true,
			},
			0.3
		)
	)
	assert_bool(view.is_climbing()).is_false()
