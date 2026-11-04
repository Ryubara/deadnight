# The wall tier (#858, docs/design/weapons.md "The wall tier"): a wall spot sells only the weaker
# guns, on every map; the stronger ones come only from the box (the prize crane). Each test holds
# both maps to it: the lot's markers and the second map's markers, the weapons each map's tuning
# prices, the bots' shopping lists, and the box's pool.
extends GdUnitTestSuite

const SMALLMAP_SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const SMALLMAP_TUNING := "res://world/smallmap/smallmap_tuning.tres"
const BOX := &"crane_play"

## The ids of the guns the maintainer put in the box for the second map (#858); each is checked
## whether or not the catalogue has it yet, so no map can give one a wall.
const BOX_ONLY: Array[StringName] = [&"weapon_pump_870", &"weapon_mp5", &"weapon_m4a1"]

var _lot_spots: Array[Dictionary] = []
var _small_spots: Array[Dictionary] = []
var _lot_rules: RulesTuning
var _small_rules: RulesTuning
var _small_map: MapTuning


func before_test() -> void:
	var world := auto_free(NightWorld.new()) as NightWorld
	add_child(world)
	world.greybox = load(LotFixture.SCENE).instantiate() as Node3D
	world.add_child(world.greybox)
	_lot_spots = world.shop_spots()
	_lot_rules = RulesFixture.tuning()
	_small_map = load(SMALLMAP_TUNING) as MapTuning
	_small_rules = _small_map.apply(RulesFixture.tuning())
	var small := auto_free((load(SMALLMAP_SCENE) as PackedScene).instantiate()) as Node3D
	add_child(small)
	_small_spots.clear()
	for marker in small.get_node("ShopSpots").get_children():
		(
			_small_spots
			. append(
				{
					"name": marker.name,
					"kind": StringName(marker.get_meta("kind")),
					"shop_id": StringName(marker.get_meta("shop_id")),
				}
			)
		)


func _walls(spots: Array[Dictionary]) -> Array[Dictionary]:
	return spots.filter(func(spot: Dictionary) -> bool: return spot["kind"] == &"wall")


func _check_walls(spots: Array[Dictionary], map_name: String) -> void:
	var walls := _walls(spots)
	assert_int(walls.size()).override_failure_message(map_name + " has no wall").is_greater(0)
	for spot in walls:
		var id: StringName = spot["shop_id"]
		(
			assert_bool(WallTier.wall_may_sell(id))
			. override_failure_message(
				(
					"%s sells %s (tier %d) on a wall; a wall sells up to tier %d, the rest is box only"
					% [map_name, id, WallTier.tier_of(id), WallTier.MAX_WALL]
				)
			)
			. is_true()
		)


func test_the_lots_wall_spots_sell_only_the_weaker_guns() -> void:
	_check_walls(_lot_spots, "the lot")


func test_the_second_maps_wall_spots_sell_only_the_weaker_guns() -> void:
	_check_walls(_small_spots, "the second map")


func test_every_weapon_either_map_prices_for_a_wall_is_within_the_tier() -> void:
	for pair: Array in [["the lot", _lot_rules], ["the second map", _small_rules]]:
		for item in (pair[1] as RulesTuning).economy.items:
			if item.kind == ShopItem.Kind.WEAPON:
				(
					assert_bool(WallTier.wall_may_sell(item.id))
					. override_failure_message("%s prices %s for a wall" % [pair[0], item.id])
					. is_true()
				)


func test_the_pump_the_mp5_and_the_m4a1_have_no_wall_on_either_map() -> void:
	for spots in [_lot_spots, _small_spots]:
		for spot in _walls(spots):
			assert_array(BOX_ONLY).override_failure_message(String(spot["shop_id"])).not_contains(
				[spot["shop_id"]]
			)
	for rules in [_lot_rules, _small_rules]:
		for id in BOX_ONLY:
			assert_object((rules as RulesTuning).economy.item(id)).is_null()


func test_every_weapon_has_a_tier_on_its_definition_and_the_start_weapon_is_a_wall_one() -> void:
	for id in WeaponCatalog.IDS:
		var tier := WeaponCatalog.get_def(id).wall_tier
		(
			assert_bool(tier >= WallTier.HAND and tier <= WallTier.BOX)
			. override_failure_message(String(id))
			. is_true()
		)
		assert_int(WallTier.tier_of(id)).is_equal(tier)
	assert_bool(WallTier.wall_may_sell(WeaponCatalog.START_WEAPON)).is_true()
	assert_int(WallTier.tier_of(&"weapon_rifle")).is_equal(WallTier.LONG)
	# A gun the catalogue does not know is above the wall.
	assert_int(WallTier.tier_of(&"made_up_gun")).is_equal(WallTier.BOX)


func test_every_weapon_above_the_wall_is_in_the_box_of_both_maps() -> void:
	for pair: Array in [["the lot", _lot_rules], ["the second map", _small_rules]]:
		var pool: Array[StringName] = (pair[1] as RulesTuning).economy.item(BOX).pool
		for id in WeaponCatalog.IDS:
			if WallTier.tier_of(id) > WallTier.MAX_WALL:
				(
					assert_array(pool)
					. override_failure_message(
						"%s: %s is box only and not in the box" % [pair[0], id]
					)
					. contains([StringName(WeaponCatalog.SHOP_PREFIX + String(id))])
				)


func test_the_bots_never_shop_for_a_gun_above_the_wall() -> void:
	var lists: Array[Array] = []
	lists.append(_small_map.bot_shopping)
	for skill in [
		MatchSettings.SKILL_ROOKIE, MatchSettings.SKILL_REGULAR, MatchSettings.SKILL_VETERAN
	]:
		lists.append(BotProfile.for_skill(skill).shopping)
	lists.append(BotProfile.autopilot().shopping)
	for list in lists:
		for id: StringName in list:
			if String(id).begins_with(WeaponCatalog.SHOP_PREFIX) and id != &"weapon_pistol":
				(
					assert_bool(WallTier.wall_may_sell(id))
					. override_failure_message("a bot shops for %s at a wall" % id)
					. is_true()
				)
