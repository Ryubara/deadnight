class_name UIAudio
extends RefCounted
## Sound hooks. The addon ships no sounds: a game sets `handler` to a Callable taking a cue name
## (&"hover", &"press", &"focus", &"back", &"push", &"pop") and plays whatever it likes.

static var handler := Callable()


static func play(cue: StringName) -> void:
	if handler.is_valid():
		handler.call(cue)
