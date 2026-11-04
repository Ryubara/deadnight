# The look saved in the wardrobe shows on the player in the night, and travels the way every
# player's look does: the client sends it on join, the night's look server accepts it and answers
# everyone, and the client's table dresses the bodies from it (#301).
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const WARDROBE := "res://ui/screens/customize_screen.tscn"
const TEST_PATH := "user://night_look_test.cfg"
const OTHER_ID := 2

var _saved_path: String


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## A look that is none of the presets: another preset with its own headwear and main colour.
func _own_look(preset := 4, headwear := &"ranger", primary := 7) -> CharacterLook:
	var look := CharacterLook.from_preset(preset)
	look.parts[&"headwear"] = headwear
	look.colours[&"primary"] = primary
	for i in LookCatalog.presets().size():
		assert_bool(CharacterLook.from_preset(i).equals(look)).is_false()
	return look


## Saves `look` through the real save path and reads the file back, as after a restart.
func _save(look: CharacterLook) -> void:
	LookStore.save_look(look)
	Settings.reset_defaults()
	Settings.load_from_disk()


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	return screen


func _leave(screen: NightScreen) -> void:
	UIRouter.pop()
	await UIRouter.idle
	await get_tree().process_frame
	assert_bool(is_instance_valid(screen)).is_false()


## The part meshes the model shows, sorted.
func _shown(model: Node) -> Array[String]:
	var out: Array[String] = []
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		if (meshes[mesh_name] as MeshInstance3D).visible:
			out.append(mesh_name)
	out.sort()
	return out


func _expected_parts(look: CharacterLook) -> Array[String]:
	var expected: Array[String] = SoldierLook.visible_meshes(look.to_soldier_look())
	expected.sort()
	return expected


## The colour painted into the model's atlas for `channel`.
func _atlas_colour(model: Node, channel: StringName) -> Color:
	var mesh: MeshInstance3D = SoldierLook.part_meshes(model).values()[0]
	var material := mesh.material_override as StandardMaterial3D
	var image := material.albedo_texture.get_image()
	var cell: Array = SoldierLook.catalog()["atlas"]["cells"][String(channel)]
	var swatch: int = SoldierLook.catalog()["atlas"]["swatch_px"]
	return image.get_pixel(int(cell[0]) * swatch + swatch / 2, int(cell[1]) * swatch + swatch / 2)


func _assert_wears(body: Player, look: CharacterLook, seat := 0) -> void:
	var model := body.get_node("Model")
	assert_array(_shown(model)).is_equal(_expected_parts(look))
	for channel in LookCatalog.colour_slots():
		var want := look.colour(channel)
		var got := _atlas_colour(model, channel)
		assert_float(got.r).is_equal_approx(want.r, 0.01)
		assert_float(got.g).is_equal_approx(want.g, 0.01)
		assert_float(got.b).is_equal_approx(want.b, 0.01)
	var band := model.find_child(CharacterAssembler.ARMBAND_NAME, true, false) as MeshInstance3D
	assert_object(band).is_not_null()
	var material := (band.mesh as TorusMesh).material as StandardMaterial3D
	assert_that(material.albedo_color).is_equal(LookCatalog.armband_colour(seat))


func test_the_saved_look_is_worn_by_the_player_in_the_night() -> void:
	var look := _own_look()
	_save(look)
	var screen := await _enter_night()
	_assert_wears(screen.night.player(), look)
	await _leave(screen)


func test_the_mouth_chosen_in_the_wardrobe_is_the_mouth_in_the_night() -> void:
	var look := _own_look()
	look.parts[&"mouth"] = &"smirk"
	_save(look)
	var screen := await _enter_night()
	var shown := _shown(screen.night.player().get_node("Model"))
	assert_array(shown).contains(["mouth__smirk"])
	assert_array(shown).not_contains(["mouth__smile"])
	await _leave(screen)


func test_the_default_look_is_worn_when_nothing_was_saved() -> void:
	var screen := await _enter_night()
	_assert_wears(screen.night.player(), CharacterLook.default_look())
	await _leave(screen)


func test_the_look_changed_in_the_wardrobe_shows_in_the_next_night() -> void:
	_save(_own_look())
	var first := await _enter_night()
	_assert_wears(first.night.player(), _own_look())
	await _leave(first)
	# Back in the wardrobe: other headwear and another main colour, saved.
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(WARDROBE, UITransition.Kind.CUT, {"seed": 3})
	await UIRouter.idle
	var wardrobe := UIRouter.top() as CustomizeScreen
	wardrobe.choose("part:headwear", LookCatalog.option_index(&"headwear", &"ballcap"))
	wardrobe.choose("colour:primary", 2)
	wardrobe.save()
	var changed := wardrobe.look.duplicate_look()
	assert_str(String(changed.parts[&"headwear"])).is_equal("ballcap")
	UIRouter.pop()
	await UIRouter.idle
	var second := await _enter_night()
	_assert_wears(second.night.player(), changed)
	assert_bool(_shown(second.night.player().get_node("Model")).has("headwear__ranger")).is_false()
	await _leave(second)


func test_the_look_travels_to_the_server_and_back_to_the_client() -> void:
	var look := _own_look(2, &"pillbox", 9)
	_save(look)
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 3)
	# The server accepted it for the player's seat, and the client's table holds what it announced.
	assert_bool(night.server.looks.looks[Night.PLAYER_ID].equals(look)).is_true()
	assert_int(night.server.looks.seats[Night.PLAYER_ID]).is_equal(0)
	assert_bool(night.looks.looks[Night.PLAYER_ID].equals(look)).is_true()
	_assert_wears(night.player(), look)
	night.queue_free()


func test_the_hud_portrait_gets_the_saved_look() -> void:
	var look := _own_look()
	_save(look)
	var screen := await _enter_night()
	var hud := screen.find_children("*", "Hud", true, false)[0] as Hud
	var member: Dictionary = hud.state.team[Night.PLAYER_ID]
	assert_bool(CharacterLook.from_dict(member["look"]).equals(look)).is_true()
	await _leave(screen)


func test_another_player_is_dressed_from_the_look_they_send() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	var theirs := _own_look(6, &"papercap", 12)
	night.link.send({"type": NightServer.JOIN, "player_id": OTHER_ID})
	night.link.send(
		{"type": NightServer.LOOK, "player_id": OTHER_ID, "packet": LookWire.look(theirs)}
	)
	NightFixture.run(night, 3)
	assert_int(night.server.looks.seats[OTHER_ID]).is_equal(1)
	assert_bool(night.server.looks.looks[OTHER_ID].equals(theirs)).is_true()
	_assert_wears(night.server.body_of(OTHER_ID), night.looks.resolved()[OTHER_ID], 1)
	night.queue_free()


func test_a_look_of_another_version_is_replaced_by_the_default_not_worn() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	night.link.send({"type": NightServer.JOIN, "player_id": OTHER_ID})
	var broken := LookWire.look(CharacterLook.from_preset(3))
	broken[1] = 99
	night.link.send({"type": NightServer.LOOK, "player_id": OTHER_ID, "packet": broken})
	NightFixture.run(night, 3)
	assert_bool(night.server.looks.looks[OTHER_ID].equals(CharacterLook.new())).is_true()
	night.queue_free()
