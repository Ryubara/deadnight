class_name ScriptWarmup
extends RefCounted
## Loads every game script, in path order, before a test run starts (Deadnight #1231).
##
## A script that another script only names (a `class_name` in a type or a call) is read as that
## script's dependency, and one that nothing ever loads as a script of its own was still in use
## when the process quit: `ObjectDB instances were leaked at exit` and `N resources still in use`,
## with its statics, fonts, textures and the scripts they reach, up to 1,000 objects, with every
## test green (CI fails on those two lines). Which scripts that was depended on which suites the
## shard held, so a new test file moved the split and the leak came and went between pull
## requests. Every script loaded as itself, first and in one fixed order, leaves nothing: the
## same shard that leaked 996 objects leaves none. Docs: docs/research/test-exit-leaks.md.

## The folders of game code a suite names. Not `tests` (a capture script there holds a scene for
## the whole run) and not `tools` (dev scripts that are not part of the game).
const ROOTS: Array[String] = [
	"res://addons/gds_ui",
	"res://core",
	"res://gameplay",
	"res://net",
	"res://ui",
	"res://world",
]


## Loads every script under `roots`, folders and files in name order; returns how many.
static func load_all(roots: Array[String] = ROOTS) -> int:
	var loaded := 0
	for root in roots:
		loaded += _load_folder(root)
	return loaded


static func _load_folder(folder: String) -> int:
	var loaded := 0
	var files := DirAccess.get_files_at(folder)
	files.sort()
	for file in files:
		if file.ends_with(".gd"):
			load(folder.path_join(file))
			loaded += 1
	var folders := DirAccess.get_directories_at(folder)
	folders.sort()
	for sub in folders:
		loaded += _load_folder(folder.path_join(sub))
	return loaded
