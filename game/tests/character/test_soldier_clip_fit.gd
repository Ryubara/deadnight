# Limbs and garments stay out of the body in the clips the player plays (Deadnight #895), measured
# by `ClipFit` (a vertex of one part inside the surface of another, deeper than its tolerance):
# - the menu's soldier, the maintainer's shot: no arm or armband in the body with any weapon (#987
#   moved the long guns' grips out of the jacket, and nothing is recorded for it);
# - every hair cut, hat, pair of glasses and neckwear out of the shoulders in every clip;
# - the arms in the clips: no forearm or hand deeper than the tolerance in any clip, sampled at
#   eight frames (four missed a windup's key pose); none may be recorded (#939 reworked the clips
#   that did: the dual pistols, the strikes, downed, crawl and revive, the sprints, the repair);
# - the armbands no deeper than recorded in `clip_fit_recorded.json`, and those records small.
# Docs: docs/research/soldier-parts.md, "Fit".
extends GdUnitTestSuite

const RECORDED := "res://tests/character/clip_fit_recorded.json"
## How much deeper than recorded a clip may go (the sampling's own spread), metres.
const SLACK := 0.005
## The deepest an armband may be recorded at in a clip, metres.
const ARMBAND_MOST := 0.055
## Frames sampled in each clip for the arms (the clips are short: a windup's key pose lies between
## four samples).
const ARM_SAMPLES := 8
## The looks the arms are sampled on: hers in rolled sleeves (the maintainer's), his in a jacket.
const ARM_LOOKS: Array[int] = [10, 0]
## One look per head piece, each on a tall collar (the closest to the head): [preset, parts].
const HEAD_LOOKS := [
	[0, {&"hair": &"crew", &"eyewear": &"glasses", &"neck": &"scarf"}],
	[0, {&"hair": &"pompadour", &"eyewear": &"sunglasses", &"neck": &"bowtie"}],
	[0, {&"hair": &"flattop", &"eyewear": &"goggles"}],
	[8, {&"hair": &"ponytail", &"torso": &"jacket"}],
	[8, {&"hair": &"bob", &"torso": &"jacket", &"neck": &"scarf"}],
	[8, {&"hair": &"curls", &"torso": &"jacket", &"headwear": &"pillbox"}],
	[8, {&"hair": &"bun", &"torso": &"jacket", &"headwear": &"papercap"}],
	[0, {&"headwear": &"helmet", &"torso": &"vest"}],
	[0, {&"headwear": &"ballcap"}],
	[0, {&"headwear": &"ranger", &"neck": &"scarf"}],
]
const HEAD_SAMPLES := 3

var _host: Node3D
var _ticks := 60


func before_test() -> void:
	# The probes wait two physics steps for each new surface: step faster than the game does.
	_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 480
	await RouterFixture.clear(get_tree())
	_host = Node3D.new()
	add_child(_host)


func after_test() -> void:
	Engine.physics_ticks_per_second = _ticks
	_host.free()


func _model(look: CharacterLook) -> Node3D:
	var model := CharacterAssembler.assemble(look, 0)
	_host.add_child(model)
	return model


func _lines(tag: String, found: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for check: String in found:
		var deepest: Dictionary = found[check][0]
		out.append(
			(
				"%s %s: %d vertices, deepest %.3f m (%s %s)"
				% [tag, check, found[check].size(), deepest.depth, deepest.mesh, deepest.group]
			)
		)
	return out


func test_the_menu_soldier_keeps_arms_and_armband_out_of_the_body_with_every_weapon() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	var fails: Array[String] = []
	for preset in ARM_LOOKS:
		var known: Dictionary = recorded.get("menu %d" % preset, {})
		for id in MenuHero.available():
			var found := await ClipFit.menu_fit(_host, CharacterLook.from_preset(preset), id)
			for check: String in found:
				var depth: float = found[check][0].depth
				var allowed: float = known.get(String(id), {}).get(check, ClipFit.TOLERANCE) + SLACK
				if depth > allowed:
					fails.append_array(_lines("%d %s" % [preset, id], {check: found[check]}))
	assert_array(fails).is_empty()


## The menu's holds keep every sleeve out (#987): nothing may be recorded for them.
func test_nothing_is_recorded_for_the_menu() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	for preset in ARM_LOOKS:
		assert_bool(recorded.has("menu %d" % preset)).is_false()


func test_head_pieces_stay_out_of_the_shoulders_in_every_clip() -> void:
	var fails: Array[String] = []
	for entry: Array in HEAD_LOOKS:
		var look := CharacterLook.from_preset(entry[0])
		for slot: StringName in entry[1]:
			look.parts[slot] = entry[1][slot]
		var model := _model(look)
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var report := await ClipFit.new(fit, model).sample_clips([], ["head pieces"], HEAD_SAMPLES)
		for clip: String in report:
			var e: Dictionary = report[clip]["head pieces"]
			fails.append("%s %s: %.3f m at %.2f s (%s)" % [entry[1], clip, e.depth, e.at, e.mesh])
		fit.free_bodies()
		_host.remove_child(model)
		model.free()
	assert_array(fails).is_empty()


func test_no_clip_puts_an_arm_deeper_into_the_body_than_recorded() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	var fails: Array[String] = []
	for preset in ARM_LOOKS:
		var model := _model(CharacterLook.from_preset(preset))
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var fit := BodyFit.new(_host, skeleton)
		var report := await ClipFit.new(fit, model).sample_clips([], [], ARM_SAMPLES)
		var known: Dictionary = recorded.get(str(preset), {})
		for clip: String in report:
			for check: String in report[clip]:
				var depth: float = report[clip][check].depth
				var allowed: float = known.get(clip, {}).get(check, ClipFit.TOLERANCE) + SLACK
				if depth > allowed:
					fails.append(
						(
							"%d %s %s: %.3f m, recorded %.3f"
							% [preset, clip, check, depth, allowed - SLACK]
						)
					)
		fit.free_bodies()
		_host.remove_child(model)
		model.free()
	assert_array(fails).is_empty()


## No clip may put an arm into the body (#939): nothing is recorded for the arms, so the tolerance
## is the bound; the armbands' records stay small.
func test_no_clip_is_recorded_for_the_arms() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDED))
	var arms: Array[String] = []
	for preset in ARM_LOOKS:
		var known: Dictionary = recorded.get(str(preset), {})
		for clip: String in known:
			for check: String in known[clip]:
				if check.ends_with(" arm"):
					arms.append("%d %s %s" % [preset, clip, check])
				else:
					assert_float(known[clip][check]).is_less_equal(ARMBAND_MOST)
	assert_array(arms).is_empty()
