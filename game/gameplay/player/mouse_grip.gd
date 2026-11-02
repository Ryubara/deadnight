class_name MouseGrip
extends RefCounted
## Whether the player's mouse is really captured, as the platform reports it.
##
## The game asks for the mouse (`want`); the platform may take it back without telling the game:
## a browser frees the pointer lock on the first Esc (the key never reaches the page), and a
## window that loses focus frees the cursor. The engine only shows it in `Input.mouse_mode`, so
## `poll` looks every frame and says the frame the grip was found lost, once.
##
## A platform that cannot capture (a headless run) reads back `VISIBLE` for ever. Nothing is
## lost there, because nothing was held: the grip is only ever "lost" after it was seen captured.
## Tests stand in for the platform with `reader` and `writer`.

## () -> Input.MouseMode, the mode the platform reports; the engine's when not valid.
var reader := Callable()
## (Input.MouseMode) -> void, asks the platform for a mode; the engine's when not valid.
var writer := Callable()

var _wanted := false
## The platform reported the mouse captured since it was last asked for.
var _held := false
## The platform has reported the mouse captured at least once: it can capture at all.
var _can_capture := false


## Asks for the mouse captured (or freed).
func want(on: bool) -> void:
	_wanted = on
	_held = false
	_write(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


func is_wanted() -> bool:
	return _wanted


## True on the frame a mouse that was captured is found free while the game still wants it.
func poll() -> bool:
	if not _wanted:
		return false
	if _read() == Input.MOUSE_MODE_CAPTURED:
		_held = true
		_can_capture = true
		return false
	if _held:
		_held = false
		return true
	return false


## True while the game wants the mouse, this platform has captured it before, and it is not
## captured now: a lock asked for that has not come (a browser answers a frame or more later, or
## refuses outside a click). Look and fire wait for it.
func is_pending() -> bool:
	return _wanted and _can_capture and _read() != Input.MOUSE_MODE_CAPTURED


## Asks again. A browser grants a lock only to a request made while it handles a click.
func retry() -> void:
	if _wanted:
		_write(Input.MOUSE_MODE_CAPTURED)


func _read() -> Input.MouseMode:
	if reader.is_valid():
		return reader.call()
	return Input.mouse_mode


func _write(mode: Input.MouseMode) -> void:
	if writer.is_valid():
		writer.call(mode)
	else:
		Input.mouse_mode = mode
