class_name SoldierClipFile
extends RefCounted
## The Soldier's own clip files (a glb and its `clips.json`: the repair, grenade, aim-move and
## sprint files, all on the kit's rig and track paths): their clips go into the Soldier's library
## and their entries into the clip spec, so their loops and events read like any other clip's.


## Adds `clips` from `glb` to `library` (the ones it lacks) and their spec entries to `spec`;
## returns the file's own spec.
static func add(
	library: AnimationLibrary, spec: Dictionary, glb: String, spec_path: String, clips: Array
) -> Dictionary:
	var from: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var holder: Node = null
	for clip: StringName in clips:
		spec["clips"][String(clip)] = from["clips"][String(clip)]
		if library.has_animation(clip):
			continue
		# Not kept in a static: a static Animation outlives the scene tree and is reported leaked at
		# exit.
		if holder == null:
			holder = (load(glb) as PackedScene).instantiate()
		var source := holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
		library.add_animation(clip, source.get_animation(clip))
	if holder != null:
		holder.free()
	return from


## The second of `clip` at which the Body bone is lowest.
static func lowest_second(clip: Animation) -> float:
	var best := INF
	var at := 0.0
	for track in clip.get_track_count():
		if (
			clip.track_get_type(track) == Animation.TYPE_POSITION_3D
			and String(clip.track_get_path(track)).ends_with(":Body")
		):
			for key in clip.track_get_key_count(track):
				var height: float = (clip.track_get_key_value(track, key) as Vector3).y
				if height < best:
					best = height
					at = clip.track_get_key_time(track, key)
	return at


## The node path the clips' bone tracks use for the skeleton (read from the file, not assumed).
static func skeleton_track_path(anim_player: AnimationPlayer) -> String:
	var idle := anim_player.get_animation(&"Idle")
	for track in idle.get_track_count():
		var path := String(idle.track_get_path(track))
		if path.contains(":"):
			return path.get_slice(":", 0)
	return "CharacterArmature/Skeleton3D"
