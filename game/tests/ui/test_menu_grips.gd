# The menu soldier holds every weapon the way the night does (Deadnight #621): one builder
# (`HeldWeapon`) puts the weapon in the hands, so the model, its place in the hand, the arms' pose
# and the fingers are the night's. Measured the way `test_hand_grips.gd` measures the player (the
# skin against the weapon, at the end of the skeleton's update, with the same limits), and compared
# with the real player's weapon in the real test room, for every weapon the menu can show.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const STEP := 1.0 / 30.0
## Frames of the idle before a hand is measured.
const SETTLE := 30
## The files that may not put a weapon in the hand on their own: the menu's view of the soldier.
const MENU_SOURCES: Array[String] = [
	"res://ui/stage/menu_hero.gd",
	"res://ui/stage/menu_stage.gd",
	"res://ui/stage/menu_stage_view.gd",
	"res://ui/menu/loadout_panel.gd",
]
## What only the shared builder (`HeldWeapon`) is to write: the hand pose and the kit's hold.
const OWN_POSE_WORDS: Array[String] = [
	"WeaponHandsIK.new",
	"HandGripPose.new",
	"HOLD_GUN",
	"HOLD_MELEE",
	"hold_of(",
	"BoneAttachment3D"
]

var _hero: MenuHero
var _skeleton: Skeleton3D
var _want := false
var _measured := {}
var _contact: HandContact


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_hero = MenuHero.new()
	add_child(_hero)
	auto_free(_hero)
	_hero.show_look(CharacterLook.from_preset(0), &"rifle")
	_skeleton = _hero.model.find_child("Skeleton3D", true, false) as Skeleton3D
	_skeleton.skeleton_updated.connect(_on_updated)
	await get_tree().process_frame


func _on_updated() -> void:
	if not _want:
		return
	_want = false
	_contact.set_weapon(_hero.weapon)
	var fingers := _skeleton.find_child("HandGripPose", false, false) as HandGripPose
	_measured = {
		"R": _contact.measure("R"),
		"L": _contact.measure("L"),
		"left_weight": fingers.left_weight if fingers != null else -1.0,
		"right_weight": fingers.right_weight if fingers != null else -1.0,
	}


## The measurement of the hero's hands, taken after `SETTLE` frames of the idle.
func _measure() -> Dictionary:
	_contact = HandContact.new(_skeleton)
	for _i in SETTLE:
		_hero.advance(STEP)
		await get_tree().process_frame
	_want = true
	_hero.advance(STEP)
	await get_tree().process_frame
	return _measured


func _hold(id: StringName) -> void:
	_hero.hold(id)
	await get_tree().process_frame
	_skeleton = _hero.model.find_child("Skeleton3D", true, false) as Skeleton3D


func test_every_weapon_with_a_model_can_be_shown() -> void:
	var shown := MenuHero.available()
	for id in WeaponCatalog.IDS:
		var has_model := WeaponHoldMap.hold_for(id) != null
		(
			assert_bool(id in shown)
			. override_failure_message("%s: listed %s" % [id, has_model])
			. is_equal(has_model)
		)
	# Every firearm and melee weapon of the catalogue has its model today.
	assert_int(shown.size()).is_equal(WeaponCatalog.IDS.size())


func test_the_menu_holds_every_weapon_in_the_night_s_hand_with_the_night_s_grip() -> void:
	var runner := scene_runner(TEST_ROOM)
	var player := runner.find_child("Player") as Player
	player.capture_mouse = false
	var animation := player.get_node("AnimationTree") as PlayerAnimation
	var fails: Array[String] = []
	for id in MenuHero.available():
		animation.equip(id)
		await _hold(id)
		var night := animation.weapon()
		var menu := _hero.weapon
		if night == null or menu == null:
			fails.append("%s: nobody holds it (night %s, menu %s)" % [id, night, menu])
			continue
		if not night.transform.is_equal_approx(menu.transform):
			fails.append(
				"%s: weapon sits at %s, the night's at %s" % [id, menu.transform, night.transform]
			)
		var hands := _skeleton.find_child("WeaponHandsIK", false, false) as WeaponHandsIK
		var fingers := _skeleton.find_child("HandGripPose", false, false) as HandGripPose
		if hands == null or fingers == null:
			fails.append("%s: the menu has no hand pose or no fingers" % id)
			continue
		if animation.weapon_grip() != hands.grip or animation.weapon_grip() != fingers.grip:
			fails.append("%s: another grip file than the night's" % id)
		if animation.weapon_hold() != hands.hold:
			fails.append("%s: another hold than the night's" % id)
		if not animation.hands().hand_hold.is_equal_approx(hands.hand_hold):
			fails.append("%s: the right hand takes the weapon at another place" % id)
		if night.scene_file_path != menu.scene_file_path:
			fails.append("%s: another model than the night's" % id)
		# The fingers run after the arms' pose, in the menu as in the night.
		for pair in [[animation.hands(), animation.fingers()], [hands, fingers]]:
			if pair[1].get_index() <= pair[0].get_index():
				fails.append("%s: the fingers do not follow the arms' pose" % id)
	assert_array(fails).is_empty()


func test_no_menu_file_poses_the_weapon_on_its_own() -> void:
	var fails: Array[String] = []
	for path in MENU_SOURCES:
		var source := FileAccess.get_file_as_string(path)
		for word in OWN_POSE_WORDS:
			if source.contains(word):
				fails.append("%s builds the hand pose itself (%s): ask HeldWeapon" % [path, word])
	assert_array(fails).is_empty()


func test_the_hands_are_on_the_grips_of_every_weapon_with_the_nights_limits() -> void:
	assert_array(await _hands_on_grips()).is_empty()


## Every top (the hands are in the torso part) holds every weapon on its grips, his and the
## female Soldier's (#678): the grips were solved on the default jacket, and the short-sleeved tops
## once thinned the hands with the bare arm, 15-20 mm off every grip.
func test_every_top_holds_every_weapon_on_its_grips_for_him_and_her() -> void:
	var fails: Array[String] = []
	for body in [LookCatalog.MALE, LookCatalog.FEMALE]:
		for option: Dictionary in LookCatalog.options(&"torso"):
			var look := CharacterLook.default_look()
			look.set_body(body)
			look.parts[&"torso"] = option["id"]
			# A soldier of its own for each look, made the way `before_test` makes his. The one
			# before goes first: a skeleton left connected could fire the measurement before this
			# soldier's skeleton has finished its update (the tank and the rifle read 10 mm "into").
			_skeleton.skeleton_updated.disconnect(_on_updated)
			remove_child(_hero)
			_hero.free()
			_hero = MenuHero.new()
			add_child(_hero)
			_hero.show_look(look, &"rifle")
			_skeleton = _hero.model.find_child("Skeleton3D", true, false) as Skeleton3D
			_skeleton.skeleton_updated.connect(_on_updated)
			await get_tree().process_frame
			for fail in await _hands_on_grips():
				fails.append("%s %s: %s" % [body, option["id"], fail])
	assert_array(fails).is_empty()


func _hands_on_grips() -> Array[String]:
	var fails: Array[String] = []
	for id in MenuHero.available():
		await _hold(id)
		var m := await _measure()
		var hold := WeaponHoldMap.hold_for(id)
		var grip := HandGrip.for_scene(hold.scene)
		if grip == null:
			fails.append("%s: no grip" % id)
			continue
		if m.right_weight < 0.99:
			fails.append("%s: right hand not on its grip (%.2f)" % [id, m.right_weight])
		fails.append_array(HandContact.failures(id + " R", m.R, grip.right_contacts))
		if grip.has_left and hold.shouldered:
			if m.left_weight < 0.99:
				fails.append("%s: left hand not on its grip (%.2f)" % [id, m.left_weight])
			fails.append_array(HandContact.failures(id + " L", m.L, grip.left_contacts))
	return fails
