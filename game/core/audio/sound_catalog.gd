class_name SoundCatalog
extends RefCounted
## Every sound by id. The files are rendered by `tools/audio/generate.py`; the banks under
## `core/audio/banks/` say how the game plays them (one `SoundDef` each, edited in the inspector)
## and `sound_mix_default.tres` holds the numbers shared by all. The design is
## `docs/design/audio.md`.

const ROOT := "res://assets/audio/"
const BUS_MUSIC := &"Music"
const BUS_EFFECTS := &"Effects"
const BUS_UI := &"UI"
const BUS_VOICE := &"Voice"
const BUS_AMBIENCE := &"Ambience"

## The bank files the game loads, one family of sounds each. A new bank is listed here.
const BANKS: Array[String] = [
	"res://core/audio/banks/ui_menu.tres",
	"res://core/audio/banks/ui_progress.tres",
	"res://core/audio/banks/ui.tres",
	"res://core/audio/banks/weapons.tres",
	"res://core/audio/banks/firearms_2.tres",
	"res://core/audio/banks/steps.tres",
	"res://core/audio/banks/zombies.tres",
	"res://core/audio/banks/world.tres",
	"res://core/audio/banks/grenades.tres",
	"res://core/audio/banks/stings.tres",
	"res://core/audio/banks/beds.tres",
	"res://core/audio/banks/smallmap.tres",
	"res://core/audio/banks/energy.tres",
	"res://core/audio/banks/wind.tres",
	"res://core/audio/banks/perks.tres",
]

static var _defs := {}
static var _mix: SoundMix = null


static func get_def(id: StringName) -> SoundDef:
	if _defs.is_empty():
		_build()
	return _defs.get(id)


static func ids() -> Array:
	if _defs.is_empty():
		_build()
	return _defs.keys()


## The mix numbers shared by all sounds (`sound_mix_default.tres`).
static func mix() -> SoundMix:
	if _mix == null:
		_mix = load(SoundMix.SHIPPED_PATH) as SoundMix
	return _mix


## How many voices a group may hold at once (`SoundMix.group_limits`).
static func group_limits() -> Dictionary:
	return mix().group_limits


static func _build() -> void:
	for path in BANKS:
		var bank := load(path) as SoundBank
		assert(bank != null, "sound bank %s did not load" % path)
		for def in bank.sounds:
			assert(not _defs.has(def.id), "two sounds are called %s" % def.id)
			if bank.deferred:
				def.deferred = true
			_defs[def.id] = def
	SoldierVoiceCatalog.build(_add)


static func _add(id: StringName, path: String, count: int, options: Dictionary = {}) -> void:
	_defs[id] = SoundDef.make(id, ROOT + path, count, options)
