extends Node
## A still of a real screen under a typeface pairing, to judge a typeface against the game's look:
## the main menu, the settings screen, the credits or the HUD, at the window's real pixel size (so
## the type is rasterised as a player sees it, which a Movie Maker frame, always the project's
## 1920 x 1080, cannot show). Run through the no-focus launcher, not headless:
## `godot --path game res://tests/captures/menu_fonts.tscn --windowed --resolution 844x390 --
## --face=<fallback|wide|marquee|pair:<id>> --screen=menu|settings|credits|hud --out=<png>`.
## Without `--face` the tokens in force are used as they are. Settings go to a throwaway file.

const MENU := "res://ui/screens/main_menu.tscn"
const SETTINGS := "res://ui/screens/settings_screen.tscn"
const CREDITS := "res://ui/screens/credits_screen.tscn"
const RIG := "res://world/drive_in/capture_rig.tscn"
const FILE := "user://menu_fonts_capture.cfg"
## Seconds a screen is left to light its sign, bring its items in and settle its springs.
const SETTLE := 3.0
const PLAYERS := 4


func _ready() -> void:
	var args := _args()
	if args.has("face"):
		HudFonts.apply(StringName(str(args["face"])))
	UIMotion.reduced = args.has("reduced")
	Settings.path = FILE
	Settings.reset_defaults()
	var view := str(args.get("screen", "menu"))
	if view == "hud":
		await _hud()
	else:
		UIRouter.reset({"menu": MENU, "settings": SETTINGS, "credits": CREDITS}[view])
		await UIRouter.idle
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var out := str(args.get("out", "user://menu_fonts.png"))
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " window ", get_window().size)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	Settings.reset_defaults()
	get_tree().quit()


## An ordinary moment of a night over the lot: points, a hurt player, the feed, the generator.
func _hud() -> void:
	add_child((load(RIG) as PackedScene).instantiate())
	var layer := CanvasLayer.new()
	add_child(layer)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(host)
	var fixture := HudFixture.make(host, PLAYERS, 1958, true)
	fixture.into_round_one()
	var hud := fixture.hud
	var state := hud.state
	fixture.advance(HudFuel.IN_TIME + HudFuel.HOLD_TIME + HudFuel.OUT_TIME + 0.5)
	hud.banner.show_banner("ROUND 1", "THE NIGHT BEGINS", HudBanner.Rank.ROUND)
	state.set_ammo(18, 90, "Rifle")
	state.set_equipment("Revolver", 6)
	state.set_health(70.0, 100.0)
	state.set_area("The Lot", "Open the concession stand")
	for id in range(1, PLAYERS + 1):
		state.apply_event(
			{"type": &"points_changed", "player_id": id, "total": 1250 * id, "delta": 0}
		)
	hud.events_feed.push("RUBY OPENED THE CONCESSION STAND")
	hud.notices.push("CAL CONNECTED")
	for amount in [100, 60]:
		hud.gains.add_gain(&"kill", amount)
	state.apply_event({"type": &"fuel_changed", "fuel": 62.0, "delta": 0.0})
	fixture.advance(HudBanner.IN_TIME + 0.3)
	await get_tree().process_frame


func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		found[parts[0]] = parts[1] if parts.size() > 1 else true
	return found
