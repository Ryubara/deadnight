extends Control
## The poster sets (#1073), one PNG into `--out=<file>`. Run it through the no-focus launcher:
## `gds godot -- --path game res://tests/captures/poster_sets.tscn --windowed --resolution
## 1920x1080 -- --out=<abs>/x.png --page=posters|tab|popup [--done=4] [--set=0] [--family=sets]
## [--phone]`. `posters` is both posters at 0, 3 and 6 panels uncovered; `tab` is the Challenges
## tab with set `--set` at `--done` of 6; `popup` the card of a finished set over the menu.
## Not part of the game.

const SETTLE := 1.5
const STEP := 1.0 / 30.0

var _args := NetArgs.new()


func _ready() -> void:
	match _args.get_string("page", "posters"):
		"posters":
			await _posters()
		"tab":
			await _tab()
		"popup":
			await _popup()
		"tiles":
			await _tiles()
	await RenderingServer.frame_post_draw
	var out := _args.get_string("out")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()


func _posters() -> void:
	var ground := ColorRect.new()
	ground.color = Color("1b1d22")
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	var sets := PosterSets.shipped().all()
	for row in sets.size():
		for column in 3:
			var shown: Array[int] = []
			for i in [0, 3, 6][column]:
				shown.append(i)
			var art := PosterArt.make(sets[row], 280.0, shown)
			art.position = Vector2(30.0 + column * 310.0, 30.0 + row * 450.0)
			add_child(art)
	await get_tree().process_frame


## The prize pieces as the equip screen lists them: locked (how to get them) and owned.
func _tiles() -> void:
	var ground := ColorRect.new()
	ground.color = Color("1b1d22")
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	var plates := PlateCatalog.shipped()
	var row := HBoxContainer.new()
	row.position = Vector2(30.0, 30.0)
	row.add_theme_constant_override(&"separation", 14)
	add_child(row)
	for owned in [false, true]:
		for poster_set in PosterSets.shipped().all():
			for kind: StringName in [PlateCatalog.CARD, PlateCatalog.EMBLEM]:
				var id := poster_set.piece(kind)
				var size := (
					Vector2(240.0, 65.0) if kind == PlateCatalog.CARD else Vector2.ONE * 64.0
				)
				row.add_child(
					PlateTile.make(kind, id, size, owned, false, plates.how_to_get(kind, id))
				)
	await get_tree().process_frame


func _tab() -> void:
	var board := FakeChallengeBoard.new()
	var poster_set := PosterSets.shipped().all()[_args.get_int("set", 0)]
	for i in _args.get_int("done", 4):
		board.feats_done.append(poster_set.challenges[i])
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1 if _args.has("phone") else 0
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ryubara", MenuProfile.xp_at(14) + 212, 485, {"rifle": 900})
	)
	shell.context.board = board
	add_child(shell)
	await get_tree().process_frame
	shell.show_tab(MenuTab.Id.CHALLENGES, false)
	var panel := shell.panel(MenuTab.Id.CHALLENGES) as ChallengesPanel
	panel.show_family(
		(
			ChallengesPanel.Family.SETS
			if _args.get_string("family", "sets") == "sets"
			else ChallengesPanel.Family.ALL
		)
	)
	for view in panel.sets():
		print("VIEW ", view.size, " ", view.position)
	var scroll := _args.get_int("scroll", 0)
	for _i in int(SETTLE / STEP):
		shell.view.stage.advance(STEP)
		await get_tree().process_frame
	if scroll > 0:
		var bar := panel.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		bar.scroll_vertical = scroll
		await get_tree().process_frame
		await get_tree().process_frame


func _popup() -> void:
	Settings.path = "user://poster_sets_capture.cfg"
	Settings.reset_defaults()
	add_child((load("res://main.tscn") as PackedScene).instantiate())
	await get_tree().process_frame
	await UIRouter.idle
	var sets := PosterSets.shipped()
	MenuPopups.announce([sets.event_of(sets.all()[_args.get_int("set", 0)])])
	var waited := 0.0
	while waited < 1.4:
		await get_tree().process_frame
		waited += get_process_delta_time()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
