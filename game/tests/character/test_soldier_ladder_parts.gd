# The ladder's wearable pieces (Deadnight #1078): appended to the catalogue, so a saved or sent look
# keeps its meaning, shown on both bodies, and within the character budgets wherever they are worn.
# How they fit is held by test_soldier_watertight.gd and test_soldier_clip_fit.gd. Docs:
# docs/research/soldier-parts.md, "The ladder's pieces".
extends GdUnitTestSuite

## Each slot as it stood before the ladder: a part is an index on the wire, so these keep their
## places for good.
const BEFORE := {
	&"headwear": [&"none", &"helmet", &"pillbox", &"ballcap", &"papercap", &"ranger"],
	&"torso": [&"vest", &"jacket", &"shirt", &"rolled", &"tank", &"letterman"],
	&"legs": [&"trousers", &"cuffed", &"shorts", &"striped"],
	&"feet": [&"boots", &"sneakers", &"shoes"],
	&"eyewear": [&"none", &"sunglasses", &"glasses", &"goggles"],
	&"neck": [&"none", &"scarf", &"bowtie"],
}
## The ladder's pieces, as the design page names them.
const PIECES := {
	&"torso/usher": "Usher's jacket",
	&"torso/coveralls": "Coveralls",
	&"legs/overalls": "Overalls",
	&"feet/saddle": "Saddle shoes",
	&"eyewear/cinema": "Cinema glasses",
	&"headwear/visor": "Projectionist's visor",
	&"neck/lanyard": "Press lanyard",
	&"neck/bolo": "Bolo tie",
	&"feet/skates": "Roller skates",
	&"legs/swing": "Swing skirt",
	&"torso/creature": "Creature tee",
	&"feet/rubber": "Rubber boots",
	&"headwear/creature": "Creature mask",
	&"neck/film": "Film-strip scarf",
	&"torso/varsity": "Varsity gold",
}
## Each piece's row on the ladder (`unlocks.json`): [level, the row's item]. The table names a piece
## its own way: a row is the design page's, a part id the catalogue's.
const RUNGS := {
	&"torso/usher": [18, &"ushers_jacket"],
	&"neck/lanyard": [19, &"press_lanyard"],
	&"eyewear/cinema": [24, &"cinema_glasses"],
	&"feet/saddle": [28, &"saddle_shoes"],
	&"legs/overalls": [31, &"overalls"],
	&"headwear/visor": [33, &"projectionists_visor"],
	&"neck/bolo": [34, &"bolo_tie"],
	&"torso/coveralls": [36, &"coveralls"],
	&"feet/skates": [38, &"roller_skates"],
	&"legs/swing": [40, &"swing_skirt"],
	&"torso/creature": [44, &"creature_tee"],
	&"feet/rubber": [46, &"rubber_boots"],
	&"headwear/creature": [48, &"creature_mask"],
	&"neck/film": [50, &"film_strip_scarf"],
	&"torso/varsity": [52, &"varsity_gold"],
}
## Each slot's order with wave one on the end: wave two only adds after it.
const WAVE_ONE := {
	&"headwear": [&"none", &"helmet", &"pillbox", &"ballcap", &"papercap", &"ranger", &"visor"],
	&"torso":
	[&"vest", &"jacket", &"shirt", &"rolled", &"tank", &"letterman", &"usher", &"coveralls"],
	&"legs": [&"trousers", &"cuffed", &"shorts", &"striped", &"overalls"],
	&"feet": [&"boots", &"sneakers", &"shoes", &"saddle"],
	&"eyewear": [&"none", &"sunglasses", &"glasses", &"goggles", &"cinema"],
	&"neck": [&"none", &"scarf", &"bowtie", &"lanyard", &"bolo"],
}
## Each fixed swatch of the atlas as it stood: a swatch that moved would repaint every part.
const SWATCHES := {
	&"lens_red": [14, 1],
	&"lens_cyan": [15, 1],
}
const BODIES: Array[StringName] = [&"male", &"female"]


func _option(slot: StringName, id: StringName) -> Dictionary:
	return LookCatalog.options(slot)[LookCatalog.option_index(slot, id)]


func test_the_pieces_are_appended_after_every_part_that_was_there() -> void:
	for before: Dictionary in [BEFORE, WAVE_ONE]:
		for slot: StringName in before:
			var ids: Array = []
			for option: Dictionary in LookCatalog.options(slot):
				ids.append(option["id"])
			assert_array(ids.slice(0, before[slot].size())).is_equal(before[slot])


func test_the_swatches_stay_where_they_were_and_the_new_ones_are_after_them() -> void:
	var cells: Dictionary = SoldierLook.catalog().atlas.cells
	for swatch: StringName in SWATCHES:
		assert_int(int(cells[swatch][0])).is_equal(SWATCHES[swatch][0])
		assert_int(int(cells[swatch][1])).is_equal(SWATCHES[swatch][1])
	for swatch: StringName in [&"gold", &"gold_shade", &"film"]:
		assert_int(int(cells[swatch][1])).is_equal(2)


## The film's frame is drawn into its swatch: sprocket holes on black, on the look's copy too.
func test_the_atlas_holds_the_film_frame_whatever_the_colours() -> void:
	var cat := SoldierLook.catalog()
	var cell: Array = cat.atlas.cells[&"film"]
	var px := int(cat.atlas.swatch_px)
	var atlas := SoldierLook.atlas_image(CharacterLook.from_preset(3).colours)
	var at := Vector2i(int(cell[0]) * px, int(cell[1]) * px)
	assert_float(atlas.get_pixelv(at).v).is_less(0.2)
	assert_float(atlas.get_pixelv(at + Vector2i(1, 1)).v).is_greater(0.8)


func test_the_creature_mask_hides_the_hair_and_the_glasses() -> void:
	for body in BODIES:
		var look := CharacterLook.from_preset(10)
		look.parts[&"body"] = body
		look.parts[&"hair"] = &"bun"
		look.parts[&"eyewear"] = &"goggles"
		look.parts[&"headwear"] = &"creature"
		var shown := SoldierLook.visible_meshes(look.to_soldier_look())
		(
			assert_bool(shown.any(func(mesh: String) -> bool: return mesh.begins_with("hair__")))
			. is_false()
		)
		(
			assert_bool(shown.any(func(mesh: String) -> bool: return mesh.begins_with("eyewear__")))
			. is_false()
		)
		# The look keeps them: taking the mask off brings them back.
		look.parts[&"headwear"] = &"none"
		shown = SoldierLook.visible_meshes(look.to_soldier_look())
		assert_array(shown).contains(["hair__bun", "eyewear__goggles"])


func test_every_piece_is_named_and_on_the_ladder_at_its_level() -> void:
	for key: StringName in PIECES:
		var slot := StringName(String(key).get_slice("/", 0))
		var id := StringName(String(key).get_slice("/", 1))
		assert_int(LookCatalog.option_index(slot, id)).is_greater(0)
		var option := _option(slot, id)
		assert_str(option["label"]).is_equal(PIECES[key])
		# The ladder's locks are the wardrobe grid's (#1065), from `unlocks.json`.
		assert_dict(option["gate"]).is_equal({"level": RUNGS[key][0]})


## The art is drawn, so each piece's row says so: a player who reaches its level is told.
func test_every_piece_is_earned_at_its_level() -> void:
	assert_int(RUNGS.size()).is_equal(PIECES.size())
	var table := LadderUnlocks.shipped()
	for key: StringName in PIECES:
		var rung: Array = RUNGS[key]
		var earned: Array = table.earned_at(rung[0]).map(
			func(row: Dictionary) -> StringName: return row["item"]
		)
		assert_array(earned).contains([rung[1]])


func test_a_look_with_a_piece_keeps_it_over_the_wire() -> void:
	for key: StringName in PIECES:
		var slot := StringName(String(key).get_slice("/", 0))
		var id := StringName(String(key).get_slice("/", 1))
		var look := CharacterLook.from_preset(0)
		look.parts[slot] = id
		assert_str(String(CharacterLook.from_bytes(look.to_bytes()).parts[slot])).is_equal(id)


func test_the_coveralls_are_a_one_piece_and_hide_the_trousers() -> void:
	for body in BODIES:
		var look := CharacterLook.from_preset(0)
		look.parts[&"body"] = body
		look.parts[&"torso"] = &"coveralls"
		look.parts[&"legs"] = &"striped"
		for mesh: String in SoldierLook.visible_meshes(look.to_soldier_look()):
			assert_bool(mesh.begins_with("legs__")).is_false()
		look.parts[&"torso"] = &"jacket"
		var shown := SoldierLook.visible_meshes(look.to_soldier_look())
		(
			assert_bool(shown.any(func(mesh: String) -> bool: return mesh.begins_with("legs__")))
			. is_true()
		)


## What hangs on the chest has her own variant: her chest stands out further than the card.
func test_the_neck_pieces_have_her_variant() -> void:
	for id: StringName in [&"lanyard", &"bolo", &"film"]:
		var look := CharacterLook.from_preset(0)
		look.parts[&"neck"] = id
		look.parts[&"body"] = &"female"
		assert_array(SoldierLook.visible_meshes(look.to_soldier_look())).contains(
			["neck__%s__female" % id]
		)


## Every piece in the place of its slot's part in every preset, on both bodies, with every mouth,
## counted as Godot draws it, near and far, with one draw call a visible part and one material.
func test_every_piece_in_every_preset_stays_within_the_budgets() -> void:
	var cat := SoldierLook.catalog()
	var model := SoldierLook.instantiate()
	add_child(auto_free(model))
	var worst := 0
	var worst_far := 0
	var fails: Array[String] = []
	for preset: Dictionary in SoldierLook.presets():
		for key: StringName in PIECES:
			for body in BODIES:
				for mouth: Dictionary in LookCatalog.options(&"mouth"):
					var look: Dictionary = preset.duplicate(true)
					look.parts[String(key).get_slice("/", 0)] = String(key).get_slice("/", 1)
					look.parts["body"] = String(body)
					look.parts["mouth"] = String(mouth["id"])
					var tris := SoldierLook.apply(model, look)
					var far := SoldierLook.far_triangles(model)
					worst = maxi(worst, tris)
					worst_far = maxi(worst_far, far)
					var tag := "%s %s %s %s" % [preset.id, key, body, mouth["id"]]
					if tris > int(cat.budget) or far > int(cat.far_budget):
						fails.append("%s: %d, far %d" % [tag, tris, far])
					if SoldierLook.visible_meshes(look).size() > 9:
						fails.append("%s: over nine parts" % tag)
	print("LADDER budgets: worst %d near, %d far" % [worst, worst_far])
	assert_array(fails).is_empty()
