extends GdUnitTestSuite
## The shotgun is a double-barrel (#684): two shells, then a break-open reload; and nothing in the
## game still calls it a pump.

## Folders of the game that ship (not the tests, which may name the old weapon to say it is gone).
const SHIPPED: Array[String] = [
	"res://core", "res://gameplay", "res://net", "res://ui", "res://world"
]
const TEXT_EXTENSIONS: Array[String] = ["gd", "tres", "tscn", "json"]

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))


func _pull(seq: int) -> Array[Dictionary]:
	return _server.apply(WeaponsFixture.fire_at(1, seq, WeaponsFixture.SHOOTER, Vector3(0, 1.1, 0)))


func _wait(seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in int(ceil(seconds / WeaponsFixture.STEP)):
		events.append_array(_server.apply(CombatAction.tick(WeaponsFixture.STEP)))
	return events


func test_the_shotgun_holds_two_shells() -> void:
	var def := WeaponsFixture.def(&"shotgun")
	assert_int(def.magazine_size).is_equal(2)
	assert_int(_server.state_of(1, &"shotgun").ammo).is_equal(2)


func test_two_shots_then_the_third_is_dry_and_a_reload_starts() -> void:
	var def := WeaponsFixture.def(&"shotgun")
	assert_array(WeaponsFixture.of(_pull(1), &"shot_fired")).has_size(1)
	_wait(def.fire_interval + 0.05)
	assert_array(WeaponsFixture.of(_pull(2), &"shot_fired")).has_size(1)
	assert_int(_server.state_of(1, &"shotgun").ammo).is_equal(0)
	_wait(def.fire_interval + 0.05)
	var third := _pull(3)
	assert_array(WeaponsFixture.of(third, &"shot_fired")).is_empty()
	assert_str(WeaponsFixture.of(third, &"fire_rejected")[0]["reason"]).is_equal("empty")
	# The empty trigger breaks it open: the reload starts by itself.
	var started := WeaponsFixture.of(third, &"reload_started")
	assert_array(started).has_size(1)
	assert_float(started[0]["seconds"]).is_equal(def.reload_time)


func test_the_reload_puts_both_shells_back_from_the_reserve() -> void:
	var def := WeaponsFixture.def(&"shotgun")
	var state := _server.state_of(1, &"shotgun")
	var reserve := state.reserve
	state.ammo = 0
	_server.apply(CombatAction.reload_weapon(1))
	assert_bool(state.is_reloading()).is_true()
	assert_int(state.ammo).is_equal(0)
	_wait(def.reload_time * 0.5)
	assert_int(state.ammo).is_equal(0)
	var done := WeaponsFixture.of(_wait(def.reload_time), &"reload_finished")
	assert_array(done).has_size(1)
	assert_int(state.ammo).is_equal(2)
	assert_int(state.reserve).is_equal(reserve - 2)


func test_a_barrel_fired_leaves_a_reload_that_loads_one_shell() -> void:
	var state := _server.state_of(1, &"shotgun")
	state.ammo = 1
	_server.apply(CombatAction.reload_weapon(1))
	_wait(WeaponsFixture.def(&"shotgun").reload_time + 0.05)
	assert_int(state.ammo).is_equal(2)


func test_the_reload_has_the_break_open_steps() -> void:
	# The break-open's own steps, with the empties kicked out and the hand at the belt (#683).
	var steps: Dictionary = WeaponSounds.RELOAD[&"shotgun"]
	assert_array(steps.keys()).contains_exactly_in_any_order(
		[&"break_open", &"eject", &"pouch", &"shells_in", &"snap_shut"]
	)
	assert_str(String(steps[&"break_open"])).is_equal("reload_shotgun_open")
	assert_str(String(ReloadMotion.for_weapon(&"shotgun").mechanism)).is_equal("break_open")


func test_the_player_is_told_the_new_name_not_the_pump() -> void:
	assert_str(WeaponsFixture.def(&"shotgun").display_name).is_equal("Double-barrel")


func test_nothing_the_game_ships_still_calls_the_shotgun_a_pump() -> void:
	var found: Array[String] = []
	for root in SHIPPED:
		_scan(root, found)
	assert_array(found).is_empty()


func _scan(folder: String, found: Array[String]) -> void:
	for name in DirAccess.get_directories_at(folder):
		_scan(folder.path_join(name), found)
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() not in TEXT_EXTENSIONS:
			continue
		var text := FileAccess.get_file_as_string(folder.path_join(file)).to_lower()
		if (
			text.contains("pump shotgun")
			or text.contains("pump-action")
			or text.contains("pump_shotgun")
		):
			found.append(folder.path_join(file))
