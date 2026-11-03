# Every map has the same machines (#859): the soda fountain, the perk coolers, the re-cut bench and
# the prize crane. The maps are found through the picker's list (`MapRegistry.playable`), so a
# third map that lands is held to this too. The scene is read without a night: its machine
# instances and the `ShopSpots` markers the night buys from.
extends GdUnitTestSuite

const SODA := "res://world/machines/soda_fountain.tscn"
const COOLER := "res://world/machines/perk_machine.tscn"
const BENCH := "res://world/machines/recut_machine.tscn"


## The scene of `info` with its machine instances and its shop markers, as dictionaries.
func _read(info: MapInfo) -> Dictionary:
	var root := auto_free(info.load_scene().instantiate()) as Node
	var instances := {SODA: 0, COOLER: 0, BENCH: 0}
	_count(root, instances)
	var kinds := {}
	var perk_ids: Array[StringName] = []
	var shop := root.get_node_or_null("ShopSpots")
	if shop != null:
		for marker in shop.get_children():
			var kind := StringName(marker.get_meta("kind", ""))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			if kind == &"perk":
				perk_ids.append(StringName(marker.get_meta("shop_id", "")))
	return {"instances": instances, "kinds": kinds, "perk_ids": perk_ids}


func _count(node: Node, instances: Dictionary) -> void:
	if instances.has(node.scene_file_path):
		instances[node.scene_file_path] += 1
	for child in node.get_children():
		_count(child, instances)


func test_the_picker_lists_the_maps_this_suite_checks() -> void:
	# Not a pin on the count: a map that lands is checked by the tests below without an edit here.
	assert_int(MapRegistry.playable().size()).is_greater_equal(2)


func test_every_map_has_a_soda_fountain_perk_coolers_and_a_re_cut_bench() -> void:
	var tonics := PerkEffects.tonic_ids(RulesFixture.tuning().economy)
	for info in MapRegistry.playable():
		var held := _read(info)
		var instances: Dictionary = held["instances"]
		var said := "map %s" % info.id
		assert_int(instances[SODA]).override_failure_message(said + ": soda fountain").is_equal(1)
		# One tonic is the fountain's; each of the others stands in a cooler of its own.
		assert_int(instances[COOLER]).override_failure_message(said + ": perk coolers").is_equal(
			tonics.size() - 1
		)
		assert_int(instances[BENCH]).override_failure_message(said + ": re-cut bench").is_equal(1)


func test_every_map_sells_each_tonic_the_re_cut_and_has_a_crane_place_to_buy_from() -> void:
	var tonics := PerkEffects.tonic_ids(RulesFixture.tuning().economy)
	for info in MapRegistry.playable():
		var held := _read(info)
		var kinds: Dictionary = held["kinds"]
		var perk_ids: Array[StringName] = held["perk_ids"]
		for tonic in tonics:
			(
				assert_bool(perk_ids.has(tonic))
				. override_failure_message("map %s: no spot sells %s" % [info.id, tonic])
				. is_true()
			)
		(
			assert_int(kinds.get(&"upgrade", 0))
			. override_failure_message("map %s: no re-cut spot" % info.id)
			. is_equal(1)
		)
		(
			assert_int(kinds.get(&"crane", 0))
			. override_failure_message("map %s: no crane spot" % info.id)
			. is_greater_equal(1)
		)
