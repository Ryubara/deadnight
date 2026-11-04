extends Node
## Capture for #678: the female Soldier in the menu and in the night, beside the male one. Her look
## (a preset of hers, `--her=N`) is saved through the real save path; the tour opens the main menu
## (the home tab and the Loadout tab, where the Character row reads Female), then a night, where a
## second player in his look (`--him=N`) joins and stands beside her under the first lamp. In the
## night it shoots the player's own shoulder camera (her hair against the view and the reticle),
## then the pair from the front, the side and the back. Each beat saves a PNG named for it into
## `--out=<folder>`. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/female_soldier_tour.tscn --resolution 1920x1080
##         -- --out=<folder> [--her=8] [--him=5] [--touch]
##
## `--touch` (with a phone's `--resolution 2340x1080`) runs the menu and the night as a phone does.
## Settings go to a throwaway file.

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const FILE := "user://female_soldier_capture.cfg"
const HIM_ID := 2
const BEAT_FRAMES := 20
## Where the pair stands: beside each other a few metres south of the first lamp.
const APART := 0.6
const BACK := 4.0
## The orbit camera: how far from the pair and how high it looks from.
const ORBIT_DISTANCE := 3.4
const ORBIT_HEIGHT := 1.1
const ORBIT_LOOK_AT := 0.75

var _out := ""
var _count := 0
var _her := 8
var _him := 5
var _touch := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--her="):
			_her = argument.trim_prefix("--her=").to_int()
		elif argument.begins_with("--him="):
			_him = argument.trim_prefix("--him=").to_int()
	_touch = "--touch" in OS.get_cmdline_user_args()
	TouchMode.device_is_touch = _touch
	Settings.path = FILE
	Settings.reset_defaults()
	LookStore.save_look(CharacterLook.from_preset(_her))
	Settings.save()
	UIMotion.reduced = true
	await _menu()
	await _night()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


func _menu() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await _beat("menu_home")
	var shells := get_tree().root.find_children("*", "MenuShell", true, false)
	if shells.is_empty():
		return
	var shell := shells[0] as MenuShell
	shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	await _beat("menu_loadout")
	var panel := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	print("[female] loadout character: ", panel.wardrobe.look.body())
	shell.tab_bar.button(MenuTab.Id.PLAY).pressed.emit()
	await _beat("menu_home_after")


func _night() -> void:
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	var night := screen.night
	await night.ready_to_play
	# The machine's real mouse must not turn the camera of a capture.
	night.player().local_input = false
	night.link.send({"type": NightServer.JOIN, "player_id": HIM_ID})
	(
		night
		. link
		. send(
			{
				"type": NightServer.LOOK,
				"player_id": HIM_ID,
				"packet": LookWire.look(CharacterLook.from_preset(_him)),
			}
		)
	)
	for _i in 30:
		await get_tree().physics_frame
	var lamp: Node3D = night.world.greybox.get_node("Field/Lamps/Lamp1")
	var her := night.server.body_of(Night.PLAYER_ID)
	var him := night.server.body_of(HIM_ID)
	# She stands on the open side of the lane (parked cars on the other), so the side shot sees her.
	her.teleport(Vector3(lamp.global_position.x + APART, 0.0, lamp.global_position.z + BACK))
	if him != null:
		him.teleport(Vector3(lamp.global_position.x - APART, 0.0, lamp.global_position.z + BACK))
	# The loading card fades out for a moment after the night is ready.
	await get_tree().create_timer(2.5).timeout
	print("[female] her voice: ", night.get_node("SoldierVoice").call(&"voice_of", Night.PLAYER_ID))
	await _beat("night_shoulder")
	# Aiming brings the shoulder camera closest to the head: hold the aim, then say how far the
	# camera is from the head against how far the hair reaches from it.
	# The night reads the body's motion from the input actions, as a person's hands give it.
	var player := night.player()
	Input.action_press(Player.ACTION_AIM)
	await _beat("night_aim")
	print("[female] aim: ", _hair_clearance(player), " aiming ", player.is_aiming())
	Input.action_release(Player.ACTION_AIM)
	# The pair seen from around them, on a camera of the capture's own; the HUD is put away.
	# (The touch layer shows itself again each frame: it stops processing too.)
	for kind in ["Hud", "TouchControls"]:
		for node in screen.find_children("*", kind, true, false):
			(node as CanvasItem).visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.fov = 52.0
	night.add_child(camera)
	camera.make_current()
	var middle := (
		(her.global_position + (him.global_position if him != null else her.global_position)) / 2
	)
	# The way she faces: her model's front (the player scene turns its model half round).
	var model := her.get_node("Model") as Node3D
	var front := model.global_basis.z
	front.y = 0.0
	front = front.normalized()
	# The side from her side of the pair, turned 20 degrees to the front so both show.
	for shot: Array in [["night_front", 0.0], ["night_side", -70.0], ["night_back", 180.0]]:
		var direction := front.rotated(Vector3.UP, deg_to_rad(shot[1]))
		camera.global_position = middle + direction * ORBIT_DISTANCE + Vector3.UP * ORBIT_HEIGHT
		camera.look_at(middle + Vector3.UP * ORBIT_LOOK_AT)
		await _beat(shot[0])


## How far the shoulder camera is from the head, how far the worn hair reaches from it (the corners
## of its box in the Head bone's space, at the body's scale) and the camera's near plane, in metres.
func _hair_clearance(player: Player) -> String:
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var head := skeleton.find_bone("Head")
	var scale := skeleton.global_basis.get_scale().x
	var reach := 0.0
	for mi: MeshInstance3D in SoldierLook.part_meshes(player.get_node("Model")).values():
		if not mi.visible or not String(mi.name).begins_with("hair__"):
			continue
		# The hair is skinned whole to Head: its bind pose takes it into the bone's space.
		var bind := Transform3D.IDENTITY
		for i in mi.skin.get_bind_count():
			if mi.skin.get_bind_name(i) == &"Head" or mi.skin.get_bind_bone(i) == head:
				bind = mi.skin.get_bind_pose(i)
		var box := mi.mesh.get_aabb()
		for i in 8:
			reach = maxf(reach, (bind * box.get_endpoint(i)).length() * scale)
	var at := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	var camera := get_viewport().get_camera_3d()
	return (
		"camera %.2f m from the head, hair reaches %.2f m, near plane %.2f m, clear by %.2f m"
		% [
			camera.global_position.distance_to(at),
			reach,
			camera.near,
			camera.global_position.distance_to(at) - reach - camera.near
		]
	)


func _beat(label: String) -> void:
	for _i in BEAT_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("beat ", label)
	if _out != "":
		_count += 1
		DirAccess.make_dir_recursive_absolute(_out)
		get_viewport().get_texture().get_image().save_png("%s/%d_%s.png" % [_out, _count, label])
