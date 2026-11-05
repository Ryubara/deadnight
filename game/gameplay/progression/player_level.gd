class_name PlayerLevel
extends RefCounted
## The level of the person at this machine, for what a level opens on their own screens (the map
## picker's locked cards). It is read from the cached profile (`ProfileSave`, the same file the
## night's `ProfileStore` keeps), because the screens before a night have no store of their own; a
## player with no file is level 1. A Guest account has a level like any other: it is the same file.
## What the *server* believes of a host is the ticket's `hostLevel` (`TicketVerifier`), never this.
##
## A test puts a level in with `use` and takes it out with `reset`, so no suite reads the
## developer's own save. A browser test of a page that asks for the probes (`WebProbe.asked`) sets
## `window.deadnight_player_level` before the game starts (`tools/web_smoke/smoke.py give_level`):
## the same thing for a build, which has no save to seed. A player's page never reads it.

## The level a test set, or 0 for the real one.
static var _forced := 0


## The level of the profile on this machine, or of the file at `path` (1 when there is none or it
## cannot be read).
static func local(path: String = ProfileSave.DEFAULT_PATH) -> int:
	if _forced > 0:
		return _forced
	if WebProbe.asked():
		var given: Variant = JavaScriptBridge.eval("window.deadnight_player_level || 0", true)
		if typeof(given) in [TYPE_INT, TYPE_FLOAT] and int(given) > 0:
			return clampi(int(given), 1, LevelCurve.MAX_LEVEL)
	var read := ProfileSave.read(path)
	var profile: Variant = read["profile"]
	return (profile as Profile).level() if profile != null else 1


## Pretends the player is level `level` (a test's).
static func use(level: int) -> void:
	_forced = clampi(level, 1, LevelCurve.MAX_LEVEL)


static func reset() -> void:
	_forced = 0
