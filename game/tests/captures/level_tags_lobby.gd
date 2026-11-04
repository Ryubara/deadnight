extends Node
## The lobby's seat list with the level and icon beside each name (#1077): the backend's member list
## as it sends it (`level`, `icon` on a member), two open seats and a bot's. One PNG into
## `--out=<file>`. Run it through the no-focus launcher, not headless:
## `gds godot -- --path game res://tests/captures/level_tags_lobby.tscn --windowed
## --resolution 1280x720 -- --out=<abs>/lobby.png [--off]`. Not part of the game.

const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SETTLE := 2.0


func _ready() -> void:
	var args := NetArgs.new()
	Settings.path = ""
	Settings.reset_defaults()
	if args.has("off"):
		Settings.set_value(SettingsService.SHOW_LEVELS, false)
	var api := LobbyFixture.FakeApi.new(self)
	var members: Array = [
		LobbyFixture.member("a", "Ruby", 1, true),
		LobbyFixture.member("b", "Moe", 2),
		LobbyFixture.member("c", "Dee", 3),
	]
	var levels := [12, 7, 23]
	for i in members.size():
		members[i]["level"] = levels[i]
		members[i]["icon"] = "level_%02d" % levels[i]
	api.lobby = LobbyFixture.lobby(members)
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.watch.every = 3600.0
	lobby.rules.bots_selector.select(1, true)
	await get_tree().create_timer(SETTLE).timeout
	# The screen scrolls to the focused Start button; the seats are at the top.
	for scroll: ScrollContainer in lobby.find_children("*", "ScrollContainer", true, false):
		scroll.scroll_vertical = 0
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	print("seat levels ", lobby.seat_levels(), " texts ", lobby.seat_texts())
	var out := args.get_string("out")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()
