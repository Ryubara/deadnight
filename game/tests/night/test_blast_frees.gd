extends GdUnitTestSuite
## A blast and the gibs of a zombie it killed free themselves when they are done: the real night
## draws 20 blasts and 100 blast kills, waits out the longest effect, and the nodes, lights and
## meshes are the count they were before (issue #929: they were kept for the rest of the night).

const SEED := 7
const BLASTS := 20
const BLAST_KILLS := 100
const SKIP_TO_ROUND := 11
const TICKS_PER_FRAME := 40
## Time runs this many times faster while the effects play out (tweens follow it).
const TIME_SCALE := 8.0
## The scorch is the longest part: 6 s held and 1 s fading, then a margin.
const SETTLE_SECONDS := 8.5
## The fireball, ring and flash are done after 0.7 s (a margin for the frames the tweens take).
const LIGHT_SECONDS := 1.5

var _scale_before := 1.0


func before_test() -> void:
	_scale_before = Engine.time_scale


func after_test() -> void:
	Engine.time_scale = _scale_before


func test_a_blast_frees_its_light_early_and_itself_when_the_scorch_fades() -> void:
	var def := load("res://gameplay/grenades/defs/frag.tres") as GrenadeDef
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	var before := _counts(holder)
	await get_tree().process_frame
	await get_tree().process_frame
	var blast := BlastEffect.new()
	holder.add_child(blast)
	blast.play(Vector3(0, 1, 0), def)
	assert_int(_counts(holder)["BlastEffect"]).is_equal(1)
	assert_int(_counts(holder)["OmniLight3D"]).is_equal(1)
	# Real time here: a fast clock lets one slow frame skip past the scorch as well.
	await get_tree().create_timer(LIGHT_SECONDS).timeout
	# The light and the two glows are gone before the scorch is: no slot held for nothing.
	assert_int(_counts(holder)["OmniLight3D"]).is_equal(0)
	assert_int(_counts(holder)["MeshInstance3D"]).is_equal(1)
	Engine.time_scale = TIME_SCALE
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	assert_bool(is_instance_valid(blast)).is_false()
	assert_dict(_counts(holder)).is_equal(before)


func test_gibs_free_themselves_and_stop_being_integrated() -> void:
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	var gibs := BlastEffect.new()
	holder.add_child(gibs)
	gibs.gibs(Vector3(0, 1, 0), Vector3.UP, 5)
	assert_int(_counts(holder)["MeshInstance3D"]).is_equal(6)
	Engine.time_scale = TIME_SCALE
	await get_tree().create_timer(LIGHT_SECONDS * 3.0).timeout
	assert_bool(is_instance_valid(gibs)).is_false()
	assert_int(_counts(holder)["MeshInstance3D"]).is_equal(0)


func test_a_night_that_blasts_and_gibs_ends_with_the_nodes_it_began_with() -> void:
	var night := Night.new()
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, SEED)
	night.server.rules.round_number = SKIP_TO_ROUND
	night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))
	night.ticks_per_frame = TICKS_PER_FRAME
	var guard := 0
	while night.state.zombies.size() < 8 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	night.set_physics_process(false)
	var ids: Array[int] = []
	for zombie in night.state.zombies:
		ids.append(zombie["id"])
	assert_int(ids.size()).is_greater_equal(8)
	var before := _counts(night)
	for k in BLASTS:
		night.view.draw_event(
			{"type": &"grenade_exploded", "grenade_id": 9000 + k, "point": Vector3(k, 0, 0)}
		)
	for k in BLAST_KILLS:
		(
			night
			. view
			. draw_event(
				{
					"type": &"zombie_removed",
					"zombie_id": ids[k % ids.size()],
					"zone": RulesAction.ZONE_BLAST,
					"killer_id": 1,
					"cause": &"killed",
				}
			)
		)
	var during := _counts(night)
	print("blast counts: before %s during %s" % [before, during])
	assert_int(during["BlastEffect"]).is_equal(BLASTS + BLAST_KILLS)
	Engine.time_scale = TIME_SCALE
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var after := _counts(night)
	print("blast counts after: %s nodes %d" % [after, int(after["nodes"])])
	assert_dict(after).is_equal(before)
	night.queue_free()


## BlastEffect, light, mesh and all node counts under `root`.
func _counts(root: Node) -> Dictionary:
	return {
		"BlastEffect": root.find_children("*", "BlastEffect", true, false).size(),
		"OmniLight3D": root.find_children("*", "OmniLight3D", true, false).size(),
		"MeshInstance3D": root.find_children("*", "MeshInstance3D", true, false).size(),
		"nodes": root.find_children("*", "", true, false).size(),
	}
