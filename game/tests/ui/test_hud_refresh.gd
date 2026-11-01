# What the HUD costs when little changes (#142): the break countdown, a batch of events from one
# tick, and readings that did not change. Counts come first (changes announced, nodes made); the
# time budget is loose, only there to catch a return of the 41 to 45 ms a 24-kill tick once took.
extends GdUnitTestSuite

## Zombies asked for in the kill batch; round one with four players has 17, and all of them dying
## in one tick is 58 events (hits, kills, points, the round's end).
const KILLS := 24
## Round one holds fewer zombies than it did, so the batch is a little smaller; it is still a crowd.
const BATCH_EVENTS := 40
## Wall-clock budget for the HUD to take such a batch, headless. Measured at about 2 ms after the
## fix and 41 to 45 ms before it; the slack is for a slow machine.
const BATCH_BUDGET_MS := 15.0
const BREAK_FRAMES := 60
const FRAME := 1.0 / 60.0

var _host: Control
var _scope: Node
var _nodes_made := 0
var _changes := 0


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _scope.is_ancestor_of(node):
		_nodes_made += 1


## Starts counting the nodes made under `scope` and the changes `hud` announces. (The feed and
## the gains make nodes for the events that happen; the parts counted here must not.)
func _watch(hud: Hud, scope: Node = null) -> void:
	_scope = scope if scope != null else hud
	_nodes_made = 0
	_changes = 0
	get_tree().node_added.connect(_on_node_added)
	hud.state.changed.connect(func() -> void: _changes += 1)


func _in_break(players := 4) -> HudFixture:
	var fixture := HudFixture.make(_host, players)
	fixture.act(RulesAction.start())
	assert_int(fixture.hud.state.phase).is_equal(HudState.PHASE_BREAK)
	return fixture


func test_the_break_countdown_wakes_the_hud_once_a_second_and_makes_no_nodes() -> void:
	var fixture := _in_break()
	var hud := fixture.hud
	await await_idle_frame()
	_watch(hud)
	for _i in BREAK_FRAMES:
		hud.state.tick(FRAME)
	# One second of break: the number on screen changes once.
	assert_int(_changes).is_less_equal(2)
	assert_int(_nodes_made).is_equal(0)


func test_the_party_rows_are_made_once_for_the_roster_not_per_change() -> void:
	var fixture := _in_break(4)
	var hud := fixture.hud
	assert_array(hud.points.shown).has_size(4)
	await await_idle_frame()
	_watch(hud, hud.points)
	fixture.act(RulesAction.set_downed(2, true))
	fixture.act(RulesAction.set_downed(2, false))
	hud.state.set_player_name(2, "Moe the Second")
	# A down state or a name rewrites a row's text; no row is made or freed.
	assert_int(_nodes_made).is_equal(0)
	assert_str(hud.points.shown[1]["name"]).is_equal("Moe the Second")
	fixture.act(RulesAction.remove_player(3))
	assert_array(hud.points.shown).has_size(3)
	assert_int(hud.points._column.get_child_count()).is_equal(3)


func test_readings_that_did_not_change_announce_nothing() -> void:
	var fixture := _in_break(2)
	var hud := fixture.hud
	hud.state.set_health(80.0, 100.0)
	hud.state.set_ammo(12, 90, "Shotgun")
	hud.state.set_equipment("Flare", 2)
	hud.state.set_area("The Lot", "Open the door")
	hud.state.set_prompt(&"buy_door", "Door", 350)
	await await_idle_frame()
	_watch(hud)
	for _i in BREAK_FRAMES:
		hud.state.set_health(80.0, 100.0)
		hud.state.set_ammo(12, 90, "Shotgun")
		hud.state.set_equipment("Flare", 2)
		hud.state.set_area("The Lot", "Open the door")
		hud.state.set_prompt(&"buy_door", "Door", 350)
		hud.state.set_player_name(1, "Ruby")
	assert_int(_changes).is_equal(0)
	assert_int(_nodes_made).is_equal(0)


func _kill_batch(fixture: HudFixture) -> Array[Dictionary]:
	var ids := fixture.spawn(KILLS)
	var batch: Array[Dictionary] = []
	for id in ids:
		batch.append_array(
			fixture.rules.apply(
				RulesAction.hit(1 + id % 4, id, RulesAction.ZONE_HEAD, HudFixture.KILLING)
			)
		)
	return batch


func test_a_batch_of_events_is_announced_once_and_costs_little() -> void:
	var fixture := HudFixture.make(_host, 4)
	fixture.into_round_one()
	var hud := fixture.hud
	var batch := _kill_batch(fixture)
	assert_int(batch.size()).is_greater_equal(BATCH_EVENTS)
	await await_idle_frame()
	_watch(hud, hud.points)
	var started := Time.get_ticks_usec()
	hud.feed(batch)
	var took_ms := float(Time.get_ticks_usec() - started) / 1000.0
	assert_int(_changes).is_less_equal(1)
	assert_int(_nodes_made).is_equal(0)
	assert_float(took_ms).is_less(BATCH_BUDGET_MS)
	# The whole batch landed: every zombie of the round is down.
	assert_int(hud.state.zombies_left).is_equal(0)


func test_events_fed_one_at_a_time_never_rebuild_the_party() -> void:
	# A client that feeds events as they arrive gets at most one change each, and none of them
	# makes a row.
	var fixture := HudFixture.make(_host, 4)
	fixture.into_round_one()
	var hud := fixture.hud
	var batch := _kill_batch(fixture)
	await await_idle_frame()
	_watch(hud, hud.points)
	for event in batch:
		hud.state.apply_event(event)
	assert_int(_changes).is_less_equal(batch.size())
	assert_int(_nodes_made).is_equal(0)
