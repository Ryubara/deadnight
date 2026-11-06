extends Node
## What a player sees when a join fails, 30 s in: `--out=PATH.png` (#1366).

const NOBODY := "ws://127.0.0.1:1"
const WAIT_SECONDS := 32.0


func _ready() -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	NightScreen.join_url = NOBODY
	NightScreen.warm_up_enabled = true
	var screen := (load("res://ui/screens/night_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.screen_enter()
	await get_tree().create_timer(WAIT_SECONDS).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
