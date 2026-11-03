extends Node
## The weapon slot strip (#682) for captures, two ways, saved as PNGs of the window:
##
## `--mode=night`: the real night with the strip over the lot. The pistol is in hand (slot 2 lit),
## the first slot's pick puts the crowbar in hand, the second's puts the pistol back, and a bought
## rifle takes the slot of the weapon it replaces. `--touch` adds the phone's touch controls, to see
## the strip beside the buttons; `--solo` keeps a night's own start (the pistol alone) and shows the
## empty second place. Each stage writes `<out>/<tag>_<stage>.png` and prints what the
## server says is in hand.
##
## `--mode=pairs`: a contact sheet of the strip for every pair of catalogue weapons, once with the
## first lit and once with the second, on real `HudSlots` parts, labelled with the weapons.
## Also measures each silhouette: it must have pixels, not touch the picture's edge, and point its
## barrel to the right (the end with the barrel is the thinner one).
##
## Run through the no-focus launcher at the size to see:
## `gds godot -- --path game res://tests/captures/weapon_slots_tour.tscn --resolution 1280x720 --
## --mode=night --out=<folder> --tag=720p`.

const SETTLE_FRAMES := 20
const SHEET_COLUMNS := 6
const SHEET_CELL := Vector2(318.0, 104.0)

var _out := ""
var _tag := "tour"
var _night: Night
var _seq := 0
var _pending_slot := 0


func _ready() -> void:
	var args := _args()
	_out = String(args.get("out", "user://"))
	_tag = String(args.get("tag", "tour"))
	DirAccess.make_dir_recursive_absolute(_out)
	# The mouse and keys of whoever sits at the machine must not touch a recording.
	match String(args.get("mode", "night")):
		"pairs":
			await _pairs()
		_:
			await _night_tour(args.has("touch"), args.has("solo"))
	get_tree().quit()


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg).trim_prefix("--")
		var parts := text.split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found


# --- The night ---


func _night_tour(with_touch: bool, solo: bool) -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	if with_touch:
		TouchMode.device_is_touch = true
		var controls := TouchControls.new()
		controls.state = hud.state
		controls.active_changed.connect(func(active: bool) -> void: hud.touch_layout = active)
		controls.safe_insets_changed.connect(
			func(insets: Vector4) -> void: hud.set_safe_insets(insets)
		)
		layer.add_child(controls)
	add_child(layer)
	var tuning := (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).duplicate(true) as RulesTuning
	)
	if not solo:
		tuning.economy.start_weapons = [&"weapon_crowbar", &"weapon_pistol"]
	_night = Night.new()
	_night.hud = hud
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 7, tuning)
	_night.player().local_input = false
	_night.player().capture_mouse = false
	_night.ticked.connect(_send)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	_night.state.apply_events(_night.server.rules.apply(RulesAction.grant_points(1, 9000)))
	_night.player().camera_rig.camera().make_current()
	await _settle()
	if solo:
		# A night's own start: the pistol alone, the second place empty, and its key does nothing.
		await _shot("0_pistol_alone")
		_pick(2)
		await _settle()
		await _shot("0_key_2_on_an_empty_slot")
		return
	await _shot("1_pistol_in_hand")
	_pick(1)
	await _settle()
	await _shot("2_slot_1_crowbar")
	_pick(2)
	await _settle()
	await _shot("3_slot_2_pistol")
	# The rifle bought with the pistol in hand takes the pistol's place; slot 1 stays the crowbar.
	_night.state.apply_events(_night.server.combat.apply(CombatAction.give_weapon(1, &"rifle")))
	await _settle()
	await _shot("4_rifle_replaces_slot_2")
	_pick(1)
	await _settle()
	await _shot("5_slot_1_crowbar_rifle_waits")


## Asks for a slot at the next tick, as the key does.
func _pick(slot: int) -> void:
	_pending_slot = slot


func _send() -> void:
	var command := NightCommand.new()
	command.slot = _pending_slot
	_pending_slot = 0
	_seq += 1
	_night.link.send(command.to_dict())


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var held := String(_night.state.me()["weapon"])
	print("STAGE %s in hand: %s, carried: %s" % [stage, held, _night.server.combat.carried(1)])
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _tag, stage])


# --- Every pair ---


func _pairs() -> void:
	var ids := WeaponCatalog.IDS
	var cells: Array[Control] = []
	var layer := CanvasLayer.new()
	add_child(layer)
	var back := ColorRect.new()
	back.color = UITokens.active().surface
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var index := 0
	var strips: Array[HudSlots] = []
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			for held in [1, 2]:
				var cell := _strip_for(ids[a], ids[b], held)
				var column := index % SHEET_COLUMNS
				var row := index / SHEET_COLUMNS
				cell.position = Vector2(14.0 + column * SHEET_CELL.x, 8.0 + row * SHEET_CELL.y)
				layer.add_child(cell)
				cells.append(cell)
				strips.append(cell.get_node("Strip") as HudSlots)
				index += 1
	await _settle()
	await _settle()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_pairs.png" % [_out, _tag])
	print("PAIRS %d strips for %d weapons" % [strips.size(), ids.size()])
	await _measure(ids)


## A labelled strip for the pair with the weapon in `held` (1 or 2) lit.
func _strip_for(first: StringName, second: StringName, held: int) -> Control:
	var holder := Control.new()
	var state := HudState.new()
	var strip := HudSlots.new()
	strip.name = "Strip"
	strip.position = Vector2(0.0, 28.0)
	holder.add_child(strip)
	strip.bind(state)
	var arms := {first: [6, 24, 0], second: [6, 24, 0]}
	var me := {
		"weapon": first if held == 1 else second,
		"ammo": 6,
		"reserve": 24,
		"reloading": false,
		"arms": arms
	}
	HudLoadout.sync(me, state)
	var caption := HudStyle.label(
		"%s + %s  (%d lit)" % [first, second, held], HudStyle.MIN_TEXT, UITokens.active().ink_muted
	)
	holder.add_child(caption)
	return holder


## Reads every weapon's silhouette back from its viewport: it must have pixels, stay off the
## picture's edge, and have its barrel (the narrow end) on the right.
func _measure(ids: Array[StringName]) -> void:
	var drawn := WeaponSilhouettes.new()
	add_child(drawn)
	for id in ids:
		drawn.texture_of(id)
	await _settle()
	await RenderingServer.frame_post_draw
	var bad := 0
	for id in ids:
		var image := drawn.texture_of(id).get_image()
		var box := _opaque_box(image)
		var right_height := _column_height(image, box, 0.9)
		var left_height := _column_height(image, box, 0.1)
		var touches := (
			box.position.x <= 0
			or box.position.y <= 0
			or box.end.x >= image.get_width()
			or box.end.y >= image.get_height()
		)
		var verdict := "ok"
		if box.size.x <= 0 or touches:
			verdict = "BAD (empty or touches the edge)"
			bad += 1
		print(
			(
				"SILHOUETTE %s box %s share %.2f of width, height at the right end %d, at the left %d: %s"
				% [
					id,
					box,
					box.size.x / float(image.get_width()),
					right_height,
					left_height,
					verdict
				]
			)
		)
		image.save_png("%s/%s_silhouette_%s.png" % [_out, _tag, id])
	print("SILHOUETTES BAD %d" % bad)


func _opaque_box(image: Image) -> Rect2i:
	var box := Rect2i()
	var found := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				var pixel := Rect2i(x, y, 1, 1)
				box = pixel if not found else box.merge(pixel)
				found = true
	return box


## How many opaque pixels the column `share` of the way across the box has.
func _column_height(image: Image, box: Rect2i, share: float) -> int:
	var x := box.position.x + int(box.size.x * share)
	var count := 0
	for y in image.get_height():
		if image.get_pixel(clampi(x, 0, image.get_width() - 1), y).a > 0.5:
			count += 1
	return count
