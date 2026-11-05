class_name WarmupManifest
extends RefCounted
## What a night needs loaded before it starts, found in the game's own catalogues and by reading
## the dependencies of its definition files, so a zombie look, a weapon model or a sound added
## later is picked up without anyone editing a list here. The same lists feed the stage
## (`NightWarmup`), which draws the scenes once.

## The folders of definition files that are not listed by a catalogue class.
const GRENADE_DEFS := "res://gameplay/grenades/defs/"


## Every resource file to load, once each, in the order they are needed (the sounds are loaded by
## the audio service, `Audio.preload_sound`).
static func resource_paths() -> Array[String]:
	var paths: Array[String] = []
	for look in ZombieModels.VARIANTS:
		_add(paths, ZombieModels.path_of(look))
	_add(paths, ZombieRig.EXTRA_CLIPS_FILE)
	for path in definition_paths():
		_add(paths, path)
		for dependency in dependencies_of(path):
			_add(paths, dependency)
	for scene in held_scenes():
		_add(paths, scene)
		for dependency in dependencies_of(scene):
			_add(paths, dependency)
	return paths


## The weapons' and grenades' definition files, and the repair hammer's hold (the hammer is in no
## catalogue: the repair puts it in the Soldier's hand).
static func definition_paths() -> Array[String]:
	var paths: Array[String] = []
	for id in WeaponCatalog.IDS:
		paths.append(WeaponCatalog.DIR + String(id) + ".tres")
	paths.append(PlayerAnimation.HAMMER_HOLD)
	for file in DirAccess.get_files_at(GRENADE_DEFS):
		# An export keeps a resource behind a `.remap` file: the name without it is the one to load.
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			paths.append(GRENADE_DEFS + name)
	return paths


## The files a definition file points at (a weapon's model, a grenade's effect), as `res://` paths.
static func dependencies_of(path: String) -> Array[String]:
	var found: Array[String] = []
	for entry in ResourceLoader.get_dependencies(path):
		# "uid://...::res://path" or plain "res://path": the path is the last part.
		var dependency := entry.get_slice("::", entry.get_slice_count("::") - 1)
		if dependency.begins_with("res://") and dependency != path:
			found.append(dependency)
	return found


## The scenes and meshes a definition file brings with it: what the stage draws for that weapon.
static func drawable_dependencies(paths: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for scene in held_scenes():
		_add(found, scene)
	for path in paths:
		for dependency in dependencies_of(path):
			if ResourceLoader.exists(dependency):
				var resource := load(dependency)
				if resource is PackedScene or resource is Mesh:
					_add(found, dependency)
	return found


## The scenes a hold file names as a path (not a dependency a definition file carries): the repair
## hammer's model.
static func held_scenes() -> Array[String]:
	var found: Array[String] = []
	var hold := load(PlayerAnimation.HAMMER_HOLD) as WeaponHold
	if hold != null:
		_add(found, hold.scene)
	return found


## Every file of every sound's variants.
static func sound_paths() -> Array[String]:
	var paths: Array[String] = []
	for id: StringName in SoundCatalog.ids_for_night():
		var def := SoundCatalog.get_def(id)
		for variant in range(1, def.variants + 1):
			_add(paths, def.path_for(variant))
	return paths


static func _add(paths: Array[String], path: String) -> void:
	if path != "" and not paths.has(path):
		paths.append(path)
