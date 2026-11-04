extends Node
## The plate's screens (#1070), one PNG into `--out=<file>`: `--page=cards` the equip screen,
## `--page=loadout` the Loadout tab's Plate row, `--page=scoreboard` the Tab board, `--page=report`
## the night's end board, `--page=lobby` the lobby's seats. `--empty` shows the same without cards
## or emblems (the before). Run through the no-focus launcher, not headless:
## `gds godot -- --path game res://tests/captures/plate_screens.tscn --resolution 1920x1080
## -- --out=<abs>/cards.png --page=cards`. Not part of the game.

const NAMES: Array[String] = ["Ruby", "Moe", "Dee", "Cal"]
const LEVELS: Array[int] = [12, 30, 55, 7]
const CARDS: Array[StringName] = [&"cartoon", &"dead_eye", &"midnight_show", &"the_big_take"]
const EMBLEMS: Array[StringName] = [&"admit_one", &"walk_in", &"headliner", &"pocket_money"]
const PROFILE := "user://plate_capture_profile.json"

var _args := NetArgs.new()


func _ready() -> void:
	HudPortrait.live = true
	var out := _args.get_string("out")
	match _args.get_string("page", "cards"):
		"cards":
			await _cards()
		"loadout":
			await _loadout()
		"scoreboard":
			await _scoreboard()
		"report":
			await _report()
		"lobby":
			await _lobby()
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	LobbyScreen.opener = Callable()
	get_tree().quit()


## A profile at level 30 that finished some challenges and wears two pieces.
func _profile(wearing := true) -> void:
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(30)
	profile.done = [&"f_dead_eye", &"f_walk_in", &"f_hammer", &"f_cheese", &"f_extras"]
	if wearing and not _args.has("empty"):
		profile.equipped = {"card": "dead_eye", "emblem": "walk_in"}
	ProfileSave.write(profile, [], 1, PROFILE)
	MenuProfile.profile_path = PROFILE


func _cards() -> void:
	_profile()
	var screen := (load("res://ui/screens/cards_screen.tscn") as PackedScene).instantiate()
	screen.params = {"path": PROFILE, "account": func() -> bool: return true}
	add_child(screen)
	await get_tree().process_frame


func _loadout() -> void:
	_profile()
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.context.profile = MenuProfile.from_json(MenuProfile.to_json("Ruby", 0, 0))
	shell.context.board = FakeChallengeBoard.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(shell)
	await get_tree().process_frame
	shell.tab_bar.button(MenuTab.Id.LOADOUT).pressed.emit()
	for _i in 10:
		await get_tree().process_frame


func _state() -> HudState:
	var state := HudState.new()
	state.local_player_id = 1
	for i in NAMES.size():
		state.set_player_name(i + 1, NAMES[i])
		state.team[i + 1]["points"] = 4200 - 900 * i
		state.team[i + 1]["kills"] = 61 - 12 * i
		state.set_player_level(i + 1, LEVELS[i], LEVELS[i])
		if not _args.has("empty"):
			state.set_player_plate(i + 1, CARDS[i], EMBLEMS[i])
	state.team[4]["bot"] = true
	state.round_number = 9
	return state


func _hud_layer() -> Hud:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	layer.add_child(hud)
	return hud


func _scoreboard() -> void:
	var hud := _hud_layer()
	var state := _state()
	hud.state.local_player_id = 1
	for id in state.team:
		hud.state.set_player_name(id, state.team[id]["name"])
		for key in ["points", "kills"]:
			hud.state.team[id][key] = state.team[id][key]
		hud.state.set_player_level(id, LEVELS[id - 1], LEVELS[id - 1])
		hud.state.set_player_plate(id, state.team[id]["card"], state.team[id]["emblem"])
	hud.state.team[4]["bot"] = true
	Input.action_press(Hud.SCOREBOARD_ACTION)
	hud.scoreboard.set_shown(true)
	hud.scoreboard.refresh()
	await get_tree().process_frame


func _report() -> void:
	var hud := _hud_layer()
	var board := HudEndBoard.new()
	hud.add_child(board)
	board.show_results(_state(), "THE CROWD WINS", "Leave")
	await get_tree().process_frame


func _lobby() -> void:
	var members: Array = []
	for i in 3:
		var member := {
			"userId": "u%d" % i,
			"name": NAMES[i],
			"seat": i + 1,
			"host": i == 0,
			"away": false,
			"level": LEVELS[i],
			"icon": "level_%02d" % LEVELS[i],
		}
		if not _args.has("empty"):
			member["card"] = String(CARDS[i])
			member["emblem"] = String(EMBLEMS[i])
		members.append(member)
	var held := {
		"id": "l1",
		"code": "ABC234",
		"hostId": "u0",
		"maxPlayers": 4,
		"members": members,
		"state": "open",
		"round": null,
	}
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = held
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": held, "api": api}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
