extends Node
## Plays each firearm's two voices on their own, one weapon every two seconds, at the muzzle of
## a player standing in the open, so the level of each weapon in the mix can be read off the
## recording (`--write-movie out.png --fixed-fps 30`). Prints `GUN <seconds> <weapon>`.

const FIRE := WeaponSounds.FIRE
const MOVIE_FPS := 30.0
const GAP_FRAMES := 60
## Where a shooter's muzzle is in front of the shoulder camera.
const MUZZLE := Vector3(0.4, 1.4, -1.0)

var _frame_start := 0


func _ready() -> void:
	get_window().size = Vector2i(160, 90)
	Audio.seed_random(5)
	var listener := Camera3D.new()
	add_child(listener)
	listener.make_current()
	Audio.listener = listener
	_frame_start = Engine.get_frames_drawn()
	for extra_db: float in [0.0, -8.0, -16.0]:
		for weapon: StringName in [&"pistol", &"smg", &"shotgun", &"rifle"]:
			print("GUN %.3f %s" % [(Engine.get_frames_drawn() - _frame_start) / MOVIE_FPS, weapon])
			var layers: Dictionary = FIRE[weapon]
			Audio.play(layers["shot"], MUZZLE, extra_db)
			Audio.play(layers["tail"], MUZZLE + Vector3(0.0, 0.0, -0.05), extra_db)
			for _i in GAP_FRAMES:
				await get_tree().process_frame
	Audio.stop_all()
	await get_tree().process_frame
	get_tree().quit()
