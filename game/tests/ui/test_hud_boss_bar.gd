# The boss bar: it shows while a headliner stands on the lot, follows its health from the rules'
# events and goes when it does. It sits under the banner without covering it.
extends GdUnitTestSuite

var _hud: Hud


func before_test() -> void:
	var host := auto_free(Control.new()) as Control
	host.size = Vector2(1920, 1080)
	add_child(host)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	host.add_child(_hud)


func _spawn(zombie_id: int, boss: bool, health: float = 1000.0) -> void:
	(
		_hud
		. state
		. apply_event(
			{
				"type": &"zombie_spawn_requested",
				"zombie_id": zombie_id,
				"zombie_type": &"headliner" if boss else &"walker",
				"boss": boss,
				"health": health,
			}
		)
	)


func _damage(zombie_id: int, health: float, max_health: float = 1000.0) -> void:
	(
		_hud
		. state
		. apply_event(
			{
				"type": &"zombie_damaged",
				"zombie_id": zombie_id,
				"zone": &"body",
				"health": health,
				"max_health": max_health,
			}
		)
	)


func test_the_bar_is_hidden_until_a_boss_spawns() -> void:
	assert_bool(_hud.boss_bar.visible).is_false()
	_spawn(1, false)
	assert_bool(_hud.boss_bar.visible).is_false()
	_spawn(2, true)
	assert_bool(_hud.boss_bar.visible).is_true()
	assert_str(_hud.boss_bar.caption_text).is_equal("THE PROJECTIONIST")


func test_the_bar_follows_the_boss_health() -> void:
	_spawn(2, true, 1856.0)
	assert_float(_hud.boss_bar.fractions[0]).is_equal(1.0)
	_damage(2, 928.0, 1856.0)
	assert_float(_hud.boss_bar.fractions[0]).is_equal_approx(0.5, 0.001)
	_damage(1, 5.0)
	assert_int(_hud.boss_bar.fractions.size()).is_equal(1)


func test_the_bar_goes_when_the_boss_is_removed_or_the_round_ends() -> void:
	_spawn(2, true)
	_hud.state.apply_event({"type": &"zombie_removed", "zombie_id": 3})
	assert_bool(_hud.boss_bar.visible).is_true()
	_hud.state.apply_event({"type": &"zombie_removed", "zombie_id": 2})
	assert_bool(_hud.boss_bar.visible).is_false()
	_spawn(4, true)
	_hud.state.apply_event({"type": &"round_ended", "round": 5})
	assert_bool(_hud.boss_bar.visible).is_false()


func test_two_bosses_get_a_bar_each_under_one_name() -> void:
	_spawn(2, true)
	_spawn(3, true)
	_damage(3, 100.0)
	assert_int(_hud.boss_bar.fractions.size()).is_equal(2)
	assert_str(_hud.boss_bar.caption_text).is_equal("THE PROJECTIONIST  +1")
	assert_float(_hud.boss_bar.fractions[1]).is_equal_approx(0.1, 0.001)


func test_the_bar_sits_below_the_banner_in_its_column() -> void:
	_spawn(2, true)
	_hud.banner.show_banner("ROUND 5", "7 COMING", HudBanner.Rank.ROUND)
	await get_tree().process_frame
	await get_tree().process_frame
	var banner := _hud.banner.get_global_rect()
	var bar := _hud.boss_bar.get_global_rect()
	assert_float(bar.position.y).is_greater_equal(banner.end.y - 1.0)
	assert_bool(banner.intersects(bar)).is_false()
