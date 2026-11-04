extends Node
## Capture for #1061: every mouth on the character in the game. The main menu's Loadout tab is
## driven through its own Mouth row, one shot a mouth; then a night, where a second player joins
## and both wear each mouth through the real look messages, shot close to the pair under the first
## lamp and from a teammate's distance on the game's field of view. Each beat saves a PNG named for
## it into `--out=<folder>`. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/mouth_tour.tscn --resolution 1920x1080
##         -- --out=<folder> [--her=8] [--him=5]
##
## Settings go to a throwaway file.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://mouth_capture.cfg"
const HIM_ID := 2
const BEAT_FRAMES := 12
## Where the pair stands: beside each other a few metres south of the first lamp.
const APART := 0.55
const BACK := 2.5
const FACE_HEIGHT := 1.32
const CLOSE := 2.0
const CLOSE_FOV := 30.0
## A teammate at the distance of the face research's table, on the shoulder camera's lens.
const TEAMMATE := 10.0
const TEAMMATE_FOV := 60.0
## The lot's parked cars stand in that shot: the near plane comes up to just before the pair.
const CLEAR_IN_FRONT := 1.0

var _out := ""
var _her := 8
var _him := 5


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--her="):
			_her = argument.trim_prefix("--her=").to_int()
		elif argument.begins_with("--him="):
			_him = argument.trim_prefix("--him=").to_int()
	Settings.path = FILE
	Settings.reset_defaults()
	LookStore.save_look(CharacterLook.from_preset(_him))
	Settings.save()
	UIMotion.reduced = true
	await _menu()
	LookStore.save_look(CharacterLook.from_preset(_her))
	Settings.save()
	await _night()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _menu() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var shell := get_tree().root.find_children("*", "MenuShell", true, false)[0] as MenuShell
	shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	await _beat("")
	var wardrobe := (shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel).wardrobe
	var mouths := LookCatalog.options(&"mouth")
	for i in mouths.size():
		wardrobe.choose("part:mouth", i)
		print("[mouth] row reads ", wardrobe.selector(&"mouth").text())
		await _beat("menu_%s" % mouths[i]["id"])
	shell.tab_bar.button(MenuTab.Id.PLAY).pressed.emit()
	await _beat("")


func _night() -> void:
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	var night := screen.night
	await night.ready_to_play
	# The machine's real mouse must not turn the camera of a capture.
	night.player().local_input = false
	night.link.send({"type": NightServer.JOIN, "player_id": HIM_ID})
	await _send_looks(night, &"smile")
	var lamp: Node3D = night.world.greybox.get_node("Field/Lamps/Lamp1")
	var her := night.server.body_of(Night.PLAYER_ID)
	var him := night.server.body_of(HIM_ID)
	var model := her.get_node("Model") as Node3D
	var front := model.global_basis.z
	front.y = 0.0
	front = front.normalized()
	var spot := lamp.global_position + Vector3(0.0, 0.0, BACK)
	spot.y = 0.0
	her.teleport(spot + Vector3.RIGHT * APART)
	him.teleport(spot + Vector3.LEFT * APART)
	# The loading card fades out for a moment after the night is ready.
	await get_tree().create_timer(2.5).timeout
	for kind in ["Hud", "TouchControls"]:
		for node in screen.find_children("*", kind, true, false):
			(node as CanvasItem).visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	night.add_child(camera)
	camera.make_current()
	var middle := (her.global_position + him.global_position) / 2
	var face := middle + Vector3.UP * FACE_HEIGHT
	for option: Dictionary in LookCatalog.options(&"mouth"):
		await _send_looks(night, option["id"])
		for shot: Array in [["close", CLOSE, CLOSE_FOV], ["teammate", TEAMMATE, TEAMMATE_FOV]]:
			camera.fov = shot[2]
			camera.near = maxf(0.05, shot[1] - CLEAR_IN_FRONT)
			camera.global_position = face + front * shot[1]
			camera.look_at(face)
			await _beat("night_%s_%s" % [option["id"], shot[0]])


## Both players' looks with `mouth`, by the message a client sends on join.
func _send_looks(night: Night, mouth: StringName) -> void:
	for pair: Array in [[Night.PLAYER_ID, _her], [HIM_ID, _him]]:
		var look := CharacterLook.from_preset(pair[1])
		look.parts[&"mouth"] = mouth
		var packet := LookWire.look(look)
		night.link.send({"type": NightServer.LOOK, "player_id": pair[0], "packet": packet})
	for _i in 12:
		await get_tree().physics_frame


func _beat(label: String) -> void:
	for _i in BEAT_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("beat ", label)
	if _out != "" and label != "":
		DirAccess.make_dir_recursive_absolute(_out)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, label])
