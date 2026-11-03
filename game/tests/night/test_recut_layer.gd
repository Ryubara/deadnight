extends GdUnitTestSuite
## The re-cut layer (#791): a shot of a re-cut weapon plays the futuristic layer over its report,
## whatever the weapon, and a shot of one that was not re-cut does not. It is driven like a client:
## events in (the frame says which weapons are re-cut, then a shot), sounds out.

const OWN := 1
const OTHER := 2
const MUZZLE := Vector3(0.3, 1.45, -0.4)

var _heard: Array[Dictionary] = []
var _layer: RecutLayer
var _state: ClientState


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_layer = auto_free(RecutLayer.new())
	_layer.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db})
	add_child(_layer)
	_layer.setup(_state)


## A frame in which `OWN` carries `arms` (weapon id to its tier) and `OTHER` carries the same.
func _frame(tiers: Dictionary) -> void:
	var arms := {}
	for weapon: StringName in tiers:
		arms[weapon] = [10, 40, tiers[weapon]]
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"players":
					{
						OWN: {"pos": Vector3.ZERO, "arms": arms},
						OTHER: {"pos": Vector3(9, 0, 9), "arms": arms},
					},
					"zombies": []
				}
			]
		)
	)


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _shot(weapon: StringName, shooter := OWN) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"shot_fired",
					"shooter_id": shooter,
					"weapon_id": weapon,
					"muzzle": MUZZLE,
					"ends": [],
				}
			]
		)
	)


func test_a_re_cut_weapon_s_shot_plays_the_layer() -> void:
	_frame({&"smg": 1})
	_shot(&"smg")
	assert_int(_heard.size()).is_equal(1)
	assert_str(_heard[0]["id"]).is_equal("recut_layer")


func test_a_weapon_not_re_cut_plays_none() -> void:
	_frame({&"smg": 0, &"rifle": 1})
	_shot(&"smg")
	assert_array(_heard).is_empty()


func test_the_layer_follows_the_weapon_not_the_player() -> void:
	# The player carries a re-cut rifle but fires the smg that was not.
	_frame({&"smg": 0, &"rifle": 1})
	_shot(&"smg")
	_shot(&"rifle")
	assert_int(_heard.size()).is_equal(1)


func test_every_weapon_that_can_be_re_cut_gets_the_layer_in_its_shot() -> void:
	var weapons := UpgradeTuning.shipped().catalogue_weapon_ids()
	assert_array(weapons).is_not_empty()
	for weapon: StringName in weapons:
		_heard.clear()
		_frame({weapon: 1})
		_shot(weapon)
		assert_array(_ids()).override_failure_message("%s: %s" % [weapon, _ids()]).contains(
			[&"recut_layer"]
		)


func test_every_catalogue_weapon_gets_it_once_it_is_re_cut() -> void:
	# The seventeen of the roster to come are in the catalogue as they land: all of them, a melee
	# swing and a projectile's launch included, take the layer.
	for weapon: StringName in WeaponCatalog.IDS:
		_heard.clear()
		_frame({weapon: 1})
		_shot(weapon)
		assert_array(_ids()).override_failure_message("%s: %s" % [weapon, _ids()]).contains(
			[&"recut_layer"]
		)


func test_the_own_layer_is_flat_and_a_strangers_comes_from_the_muzzle() -> void:
	_frame({&"rifle": 1})
	_shot(&"rifle", OWN)
	_shot(&"rifle", OTHER)
	assert_object(_heard[0]["at"]).is_null()
	assert_vector(_heard[1]["at"]).is_equal(MUZZLE)


func test_a_stranger_s_re_cut_is_read_from_his_own_arms() -> void:
	_frame({&"rifle": 1})
	_state.apply_events(
		[
			{
				"type": &"frame",
				"players":
				{OWN: {"arms": {&"rifle": [1, 1, 0]}}, OTHER: {"arms": {&"rifle": [1, 1, 1]}}},
				"zombies": []
			}
		]
	)
	_shot(&"rifle", OWN)
	assert_array(_heard).is_empty()
	_shot(&"rifle", OTHER)
	assert_int(_heard.size()).is_equal(1)


func test_a_quick_melee_and_other_events_play_none() -> void:
	_frame({&"smg": 1})
	(
		_state
		. apply_events(
			[
				{"type": &"quick_melee", "shooter_id": OWN, "seq": 1, "muzzle": MUZZLE, "ends": []},
				{"type": &"reload_started", "shooter_id": OWN, "weapon_id": &"smg", "seconds": 2.0},
			]
		)
	)
	assert_array(_heard).is_empty()


func test_a_weapon_with_an_element_adds_its_accent_over_the_shared_layer() -> void:
	_layer.elements = {&"smg": &"fire", &"rifle": &"shock", &"shotgun": &"explosive"}
	_frame({&"smg": 1, &"rifle": 1, &"shotgun": 1, &"pistol": 1})
	_shot(&"smg")
	assert_array(_ids()).is_equal([&"recut_layer", &"recut_fire"])
	_heard.clear()
	_shot(&"rifle")
	assert_array(_ids()).is_equal([&"recut_layer", &"recut_shock"])
	_heard.clear()
	_shot(&"shotgun")
	assert_array(_ids()).is_equal([&"recut_layer", &"recut_blast"])
	_heard.clear()
	_layer.elements = {}
	_shot(&"pistol")
	assert_array(_ids()).is_equal([&"recut_layer"])


func test_the_roster_s_elements_are_the_ones_the_design_gives() -> void:
	var table := RecutLayer.WEAPON_ELEMENTS
	assert_str(table[&"pistol"]).is_equal("explosive")
	assert_str(table[&"dual_pistols"]).is_equal("shock")
	assert_str(table[&"pump_870"]).is_equal("fire")
	assert_str(table[&"flare_gun"]).is_equal("fire")
	# The wonder weapons have none.
	assert_bool(table.has(&"ray_gun")).is_false()
	assert_bool(table.has(&"freeze_gun")).is_false()
	# The shipped table is what a layer starts with: the revolver's re-cut is explosive.
	_frame({&"pistol": 1})
	_shot(&"pistol")
	assert_array(_ids()).is_equal([&"recut_layer", &"recut_blast"])


func test_the_wonder_weapons_have_a_layer_of_their_own_and_no_accent() -> void:
	_frame({&"ray_gun": 1, &"freeze_gun": 1})
	_shot(&"ray_gun")
	_shot(&"freeze_gun")
	assert_array(_ids()).is_equal([&"recut_deep", &"recut_deep"])


func test_every_layer_is_a_sound_in_the_catalogue_that_has_a_voice_of_its_own() -> void:
	var ids: Array[StringName] = [RecutLayer.DEFAULT_LAYER, RecutLayer.WONDER_LAYER]
	for element: StringName in RecutLayer.ELEMENT_LAYERS:
		ids.append(RecutLayer.ELEMENT_LAYERS[element])
	for weapon: StringName in RecutLayer.WEAPON_ELEMENTS:
		assert_bool(RecutLayer.ELEMENT_LAYERS.has(RecutLayer.WEAPON_ELEMENTS[weapon])).is_true()
	for id in ids:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message("no sound " + id).is_not_null()
		assert_str(def.group).is_equal("recut")
		assert_int(def.variants).is_greater_equal(3)
		assert_bool(def.loop).is_false()
		for k in def.variants:
			assert_bool(ResourceLoader.exists(def.path_for(k + 1))).is_true()
	assert_int(SoundCatalog.group_limits()[&"recut"]).is_greater(0)


func test_the_layer_is_under_the_report_and_rings_on_its_own_voice() -> void:
	# A layer takes headroom from the shot it rides on: it is trimmed well under every firearm's
	# report (`energy_levels.json` has the measured sums).
	var layer := SoundCatalog.get_def(RecutLayer.DEFAULT_LAYER)
	for gun: StringName in [&"shot_pistol", &"shot_smg", &"shot_rifle", &"shot_shotgun"]:
		assert_float(layer.volume_db).is_less(SoundCatalog.get_def(gun).volume_db - 8.0)
	# It may not start twice in the same breath: a ring, not a rattle.
	assert_float(layer.cooldown).is_greater_equal(0.05)
