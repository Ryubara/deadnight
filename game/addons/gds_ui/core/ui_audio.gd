class_name UIAudio
extends RefCounted
## Sound hooks. The addon ships no sounds: a game sets `handler` to a Callable taking a cue name
## and the object that made it, and plays whatever it likes.
##
## The cues: &"hover" (a pointer arrived), &"focus" (the focus moved), &"press", &"tick" (a slider
## or a list moved one step), &"select" (a choice among several changed), &"on" and &"off" (a
## toggle), &"tab" (a page of the same screen was chosen), &"back", &"push" and &"pop" (the router),
## &"confirm" and &"refuse" (a commit that went through, and one that cannot). `source` is the
## control (or the router or screen) that made the cue; a control that has `ui_sound_role()` says
## what kind of control it is (&"button_primary", &"toggle", &"slider", ...), which is what lets a
## game give a primary button and a ghost button different sounds.

static var handler := Callable()


static func play(cue: StringName, source: Object = null) -> void:
	if handler.is_valid():
		handler.call(cue, source)
