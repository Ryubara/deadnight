extends GdUnitTestSuite
## The loadout's soldier through the real menu stage (Deadnight #940): at every turn angle the
## player can leave him at, with every weapon the catalogue can show, both hands and the muzzle are
## in front of the chest and outside the body, as the night holds the weapon. Measured at the end of
## the skeleton's update, in the soldier's own frame, with the stage live and as a still.

const TEST_PATH := "user://menu_hero_arms_test.cfg"
const STEP := 1.0 / 30.0
## The sweep of turn angles, in degrees.
const ANGLE_STEP := 15
## Metres a hand or the muzzle must be ahead of the chest plane (the plane through the torso bone,
## facing the soldier's front), and how far from the body's upright axis it must be at least.
const AHEAD_MIN := 0.12
const MUZZLE_AHEAD_MIN := 0.2
const OUTSIDE_BODY := 0.14

var _saved_path: String
var _skeleton: Skeleton3D
var _record := {}


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	UIMotion.reduced = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _view(mode: int) -> MenuStageView:
	var view := MenuStageView.new()
	view.manual = true
	view.forced_mode = mode
	add_child(view)
	auto_free(view)
	return view


## Records the hands and the torso at the end of every update of the soldier's skeleton: the arms'
## pose is only readable there (afterwards the skeleton hands back the clip's). The muzzle is read
## off the weapon, which rides the hand bone.
class Probe:
	extends RefCounted
	var hero: MenuHero
	var skeleton: Skeleton3D
	var last := {}

	func _init(of: MenuHero) -> void:
		hero = of
		skeleton = of.model.find_child("Skeleton3D", true, false) as Skeleton3D
		skeleton.skeleton_updated.connect(_on_updated)

	func _on_updated() -> void:
		var frame := hero.global_transform.affine_inverse()
		var out := {}
		for key: String in ["right", "left", "torso"]:
			var bone := {"right": "Index1.R", "left": "Index1.L", "torso": "Torso"}[key] as String
			var at := (
				skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
			)
			out[key] = frame * at.origin
		var muzzle := hero.weapon.find_child(PlayerAnimation.MUZZLE_NODE, true, false) as Node3D
		out["muzzle"] = frame * muzzle.global_position
		out["muzzle_dir"] = frame.basis * (-muzzle.global_basis.z)
		last = out


## Steps the stage and draws frames, and returns what the probe saw at the last update.
func _settle(view: MenuStageView, probe: Probe, frames := 2) -> Dictionary:
	probe.last = {}
	for _i in frames:
		# A still is not stepped: only what the screen does (a turn, a weapon) reaches the stage.
		if view.level != StageGovernor.Level.STILL:
			view.stage.advance(STEP)
		view.refresh()
		await get_tree().process_frame
	return probe.last


## What is wrong with a measurement, in words (empty when it holds). The left hand counts only when
## it holds the weapon (`left_holds`): a one-handed gun leaves it hanging at his side.
static func faults(m: Dictionary, left_holds: bool) -> Array[String]:
	var found: Array[String] = []
	var chest: Vector3 = m["torso"]
	var parts := {"right hand": m["right"], "muzzle": m["muzzle"]}
	if left_holds:
		parts["left hand"] = m["left"]
	for part: String in parts:
		var at: Vector3 = parts[part]
		var ahead := at.z - chest.z
		var need := MUZZLE_AHEAD_MIN if part == "muzzle" else AHEAD_MIN
		if ahead < need:
			found.append("%s %.2f m ahead of the chest (needs %.2f)" % [part, ahead, need])
		var across := Vector2(at.x - chest.x, at.z - chest.z).length()
		if across < OUTSIDE_BODY:
			found.append("%s %.2f m from the body's axis" % [part, across])
	if (m["muzzle_dir"] as Vector3).z < 0.3:
		found.append("barrel points %.2f of the way ahead" % (m["muzzle_dir"] as Vector3).z)
	return found


func _sweep(mode: int, reduced := false) -> Array[String]:
	UIMotion.reduced = reduced
	var view := _view(mode)
	await get_tree().process_frame
	view.show_tab(MenuTab.Id.LOADOUT)
	var failures: Array[String] = []
	var turned := 0.0
	for id in MenuHero.available():
		view.preview_look(CharacterLook.from_preset(1), id)
		var probe := Probe.new(view.stage.hero)
		var fingers := view.stage.hero.model.find_child("HandGripPose", true, false) as HandGripPose
		for degrees in range(0, 360, ANGLE_STEP):
			# The way the screen turns him: by a drag's or the stick's amount.
			view.turn(deg_to_rad(degrees) - turned)
			turned = deg_to_rad(degrees)
			var m := await _settle(view, probe)
			if m.is_empty():
				failures.append("%s at %d degrees: the skeleton never updated" % [id, degrees])
				continue
			for fault in faults(m, fingers.left_weight > 0.0):
				failures.append("%s at %d degrees: %s" % [id, degrees, fault])
	return failures


func test_every_weapon_at_every_angle_is_held_in_front_live() -> void:
	var failures := await _sweep(MenuStageView.MODE_LIVE)
	assert_array(failures).is_empty()


func test_every_weapon_at_every_angle_is_held_in_front_in_a_still() -> void:
	var failures := await _sweep(MenuStageView.MODE_STILL)
	assert_array(failures).is_empty()


func test_every_weapon_at_every_angle_is_held_in_front_with_reduced_motion() -> void:
	# The dead and the idle stand still, so the soldier is never stepped; he is still posed.
	var failures := await _sweep(MenuStageView.MODE_LIVE, true)
	assert_array(failures).is_empty()
