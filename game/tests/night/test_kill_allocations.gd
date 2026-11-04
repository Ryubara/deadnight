extends GdUnitTestSuite
## Killing zombies makes and frees nothing once the pools are warm. A shot, a kill, a number over a
## wound and a zombie coming in for the one that fell each used to build nodes, meshes and
## materials and free them again in the frame (and a freed material takes its shader with it, which
## the browser builds again): the frame of a kill cost 10 ms more than any other in the web build.
## The bot plays a night of walkers, and between its sixth kill and its twentieth no node enters the
## tree and no resource is held that was not before.
##
## Objects are counted where the fight stands still, never at a peak. A fight holds objects of its
## own that come and go with it, a different number at every frame: a torn or mended board is a
## Tween with its tweeners (3 to 5 objects each, up to nine at once), every sound that starts is a
## budget voice and the engine's playback (2 each, 20 or more at once), and every zombie alive is
## a few more. A peak taken against a start at another point of that swing was 37 to 45 locally and
## 49 and 52 elsewhere (#1102), and the count could not tell them from a kill's own objects. So the
## night is stood still twice, before the kills and after them with as many dead alive as before,
## its sounds stopped and its motions finished, and what is held is what the two readings differ by.

## Kills that fill the pools, and kills played after them.
const WARM_KILLS := 6
const PLAYED_KILLS := 14
## Frames the run may take before it gives up.
const GIVE_UP_FRAMES := 6000
## Resources the run may hold above where it began (the rules' and the bot's own bookkeeping; a kill
## that made its own material and mesh would hold dozens).
const SLACK := 8
## Objects the run may hold above where it began, at a standstill with as many dead alive. The
## bookkeeping is a few more than resources: the night's seed makes the same 7 to 10 of them, which
## come in over the first thirty kills and then stop (lazy makes of the rules and the engine, no
## node or resource among them), where a kill that holds one object of its own makes 14.
const OBJECT_SLACK := 16
## A quick night of walkers who come at once.
const SPAWN_DELAY := 0.5
## Ticks run in each physics frame, so the run takes seconds.
const TICKS_PER_FRAME := 6

var _added := 0
var _kinds: Dictionary = {}


func _night() -> Night:
	var tuning := NightFixture.only_tuning(&"walker")
	tuning.rounds.first_spawn_delay = SPAWN_DELAY
	tuning.rounds.intro_seconds = 1.0
	tuning.rounds.spawn_interval_start = 0.6
	tuning.rounds.spawn_interval_min = 0.4
	tuning.rounds.speed_base = 3.2
	tuning.rounds.count_base = 30.0
	# Few at once, so the bodies the warm-up made are enough (a night that wants more makes them).
	tuning.rounds.alive_cap_start = 5.0
	tuning.health.max_health = 1.0e6
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning, 7)
	night.server.rules.apply(RulesAction.skip_break())
	night.ticks_per_frame = TICKS_PER_FRAME
	# What the warm-up does before a night: every sound loaded, bodies made, every effect shown once.
	for id: StringName in SoundCatalog.ids():
		Audio.preload_sound(id)
	night.view.horde.prewarm(NightWarmup.PARKED_BODIES)
	night.view.effects.prewarm()
	# The bot keeps its pistol (a swap puts another weapon in its hands, which is not a kill's cost).
	night.server.combat.state_of(1, &"house_pistol").reserve = 99999
	for i in 24:
		night.view.draw_event(
			{
				"type": &"damage_dealt",
				"point": Vector3(0, 1, 0),
				"damage": 20.0 + i,
				"headshot": i % 2 == 0,
				"melee": false
			}
		)
	return night


func _on_node_added(node: Node) -> void:
	_added += 1
	var kind := (
		node.get_class() + (":" + String(node.name) if node.name.begins_with("Voice") else "")
	)
	_kinds[kind] = int(_kinds.get(kind, 0)) + 1
	if node is Skeleton3D:
		_kinds["at " + str(node.get_path())] = 1


## The bot buys what the walls offer with its points, and a weapon bought is a model made once, not
## a kill's cost: the points never gather.
func _no_points(night: Night) -> void:
	night.server.rules.players[1].points = 0


## Zombies alive in the simulation now.
func _alive(night: Night) -> int:
	return night.server.director.sim.zombies.size()


## The night stood still and quiet (`QuietCount`): its ticks stopped, its sounds and motions over.
func _quiet(night: Night) -> bool:
	night.ticks_per_frame = 0
	return await QuietCount.settle(get_tree())


## Frames until the bot has made `kills` kills.
func _play_until(night: Night, kills: int) -> void:
	var frames := 0
	while night.state.kills < kills and frames < GIVE_UP_FRAMES and not night.state.over:
		_no_points(night)
		await get_tree().physics_frame
		frames += 1
	(
		assert_int(night.state.kills)
		. override_failure_message("the bot never got there")
		. is_greater_equal(kills)
	)


func test_a_run_of_kills_adds_no_node_and_holds_no_more_resources() -> void:
	var night := await _night()
	await _play_until(night, WARM_KILLS)
	# Let what the last kills left finish, so the count starts from a quiet moment.
	await AudioSettle.until_idle(get_tree())
	var quiet_before := await _quiet(night)
	var kills_before := night.state.kills
	var alive_before := _alive(night)
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var peak_resources := resources
	night.ticks_per_frame = TICKS_PER_FRAME
	_added = 0
	get_tree().node_added.connect(_on_node_added)
	var frames := 0
	# The kills, then on to a moment with as many dead alive as at the first reading (each is a few
	# objects of its own).
	while (
		(night.state.kills < kills_before + PLAYED_KILLS or _alive(night) != alive_before)
		and frames < GIVE_UP_FRAMES
		and not night.state.over
	):
		_no_points(night)
		await get_tree().physics_frame
		frames += 1
		peak_resources = maxi(
			peak_resources, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		)
	get_tree().node_added.disconnect(_on_node_added)
	var alive_after := _alive(night)
	var quiet_after := await _quiet(night)
	var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var resources_after := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var played := night.state.kills - kills_before
	assert_int(played).override_failure_message("kills played").is_greater_equal(PLAYED_KILLS)
	(
		assert_bool(quiet_before and quiet_after)
		. override_failure_message("the night never went quiet")
		. is_true()
	)
	assert_int(alive_after).override_failure_message("dead alive").is_equal(alive_before)
	(
		assert_int(_added)
		. override_failure_message("%d nodes made over %d kills: %s" % [_added, played, _kinds])
		. is_equal(0)
	)
	(
		assert_int(maxi(peak_resources, resources_after) - resources)
		. override_failure_message("resources held: %d" % (peak_resources - resources))
		. is_less_equal(SLACK)
	)
	(
		assert_int(objects_after - objects)
		. override_failure_message("objects held: %d" % (objects_after - objects))
		. is_less_equal(OBJECT_SLACK)
	)
	night.queue_free()
