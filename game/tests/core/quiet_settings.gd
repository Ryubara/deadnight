class_name QuietSettings
extends SettingsService
## A settings service for tests: the window mode goes to a list instead of the real window, and
## every write to the file is counted, so a test can say how many writes a burst of changes made
## without touching the display it runs on.

## The window modes the service asked for, in order.
var window_calls: Array[int] = []
## How many times `save` ran.
var saves := 0


func _set_window_mode(target: DisplayServer.WindowMode) -> void:
	window_calls.append(target)


func save() -> Error:
	saves += 1
	return super.save()


## One on `path`, in `parent`'s tree so it can reach the root window; its first load and apply
## are not counted. The caller frees it (free it before the file is removed: a service with an
## unsaved change writes the file once more as it goes).
static func make(parent: Node, path: String) -> QuietSettings:
	var service := QuietSettings.new()
	service.path = path
	parent.add_child(service)
	service.window_calls.clear()
	service.saves = 0
	return service
