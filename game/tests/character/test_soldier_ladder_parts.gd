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
## Wave one, as the design page names them.
const PIECES := {
	&"torso/usher": "Usher's jacket",
	&"torso/coveralls": "Coveralls",
	&"legs/overalls": "Overalls",
	&"feet/saddle": "Saddle shoes",
	&"eyewear/cinema": "Cinema glasses",
	&"headwear/visor": "Projectionist's visor",
	&"neck/lanyard": "Press lanyard",
	&"neck/bolo": "Bolo tie",
}
## The level each opens at (`unlocks.json`, the design page's table).
const LEVELS := {
	&"torso/usher": 18,
	&"torso/coveralls": 36,
	&"legs/overalls": 31,
	&"feet/saddle": 28,
	&"eyewear/cinema": 24,
	&"headwear/visor": 33,
	&"neck/lanyard": 19,
	&"neck/bolo": 34,
}
const BODIES: Array[StringName] = [&"male", &"female"]


func _option(slot: StringName, id: StringName) -> Dictionary:
	return LookCatalog.options(slot)[LookCatalog.option_index(slot, id)]


func test_the_pieces_are_appended_after_every_part_that_was_there() -> void:
	for slot: StringName in BEFORE:
		var ids: Array = []
		for option: Dictionary in LookCatalog.options(slot):
			ids.append(option["id"])
		assert_array(ids.slice(0, BEFORE[slot].size())).is_equal(BEFORE[slot])


func test_every_piece_is_named_and_on_the_ladder_at_its_level() -> void:
	for key: StringName in PIECES:
		var slot := StringName(String(key).get_slice("/", 0))
		var id := StringName(String(key).get_slice("/", 1))
		assert_int(LookCatalog.option_index(slot, id)).is_greater(0)
		var option := _option(slot, id)
		assert_str(option["label"]).is_equal(PIECES[key])
		# The ladder's locks are the wardrobe grid's (#1065), from `unlocks.json`.
		assert_dict(option["gate"]).is_equal({"level": LEVELS[key]})


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
	for id: StringName in [&"lanyard", &"bolo"]:
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
