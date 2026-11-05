extends Node
## The hidden challenges on the equip screen (#1172), one PNG into `--out=<file>`: `--state=locked`
## shows the five hidden calling cards (or `--tab=emblem` the emblems) as a silhouette, `???` and a
## riddle; `--state=done` shows two of them earned. The window decides the layout the way a player's
## does: under 500 px on the short side it is a phone, and the menu's phone scale is put on the
## window first (`MenuScale.factor`, as the menu's shell does), or the capture shows the wrong
## layout.
## Run it through the no-focus launcher, not headless: `gds godot -- --path game
## res://tests/captures/hidden_cards.tscn --resolution 844x390 -- --out=<abs>/phone.png
## --state=locked --focus=snack_break`. Not part of the game.

const PROFILE := "user://hidden_capture_profile.json"

var _args := NetArgs.new()


func _ready() -> void:
	HudPortrait.live = true
	var window := get_window()
	get_tree().root.content_scale_factor = MenuScale.factor(window.size, 1.0)
	var done: Array[StringName] = []
	if _args.get_string("state", "locked") == "done":
		done = [&"f_snack_break", &"f_dead_on_arrival"]
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(30)
	profile.done = done
	ProfileSave.write(profile, [], 1, PROFILE)
	MenuProfile.profile_path = PROFILE
	var screen := (load("res://ui/screens/cards_screen.tscn") as PackedScene).instantiate()
	screen.params = {"path": PROFILE, "account": func() -> bool: return true}
	add_child(screen)
	await get_tree().process_frame
	if _args.get_string("tab", "card") == "emblem":
		(screen as CardsScreen).show_tab(PlateCatalog.EMBLEM)
	for _i in 4:
		await get_tree().process_frame
	# The hidden pieces are not at the top of the list: bring `--focus=<piece id>` (the end of the
	# list when none) to the top of the view.
	var kind := (
		PlateCatalog.EMBLEM if _args.get_string("tab", "card") == "emblem" else PlateCatalog.CARD
	)
	var focus := _args.get_string("focus")
	var scroll: ScrollContainer = screen.find_children("*", "ScrollContainer", true, false)[0]
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	var tile: PlateTile = (screen as CardsScreen).tile(kind, StringName(focus))
	if tile != null:
		scroll.scroll_vertical = int(tile.global_position.y - scroll.global_position.y)
	else:
		scroll.scroll_vertical = 100000
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := _args.get_string("out")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print(
			"SAVED ", out, " window ", window.size, " scale ", get_tree().root.content_scale_factor
		)
	get_tree().quit()
