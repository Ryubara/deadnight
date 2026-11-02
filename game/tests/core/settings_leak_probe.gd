extends SceneTree
## Run by `test_settings_user_file.gd` in a child Godot (not a test itself). It does what a suite
## did to the person's options file (#418): changes a value on a service built with the default
## path and frees it with the change pending (the service saves when freed), then changes the
## autoload and saves it. `--file=<path>` points both at a file of its own first, to show the
## probe really writes when it can. It prints `PROBE path=<path> wrote=<0|1>`.

const WROTE_TO := "user://leak_probe_control.cfg"


func _initialize() -> void:
	var own := false
	for argument in OS.get_cmdline_user_args():
		own = own or argument == "--file"
	var service := SettingsService.new()
	if own:
		service.path = WROTE_TO
	service.set_value(SettingsService.CAMERA_SHAKE, 0)
	var used := service.path
	service.free()
	var autoload := root.get_node("Settings") as SettingsService
	if own:
		autoload.path = WROTE_TO
	autoload.set_value(SettingsService.REDUCED_MOTION, true)
	autoload.save()
	print("PROBE path=<%s> wrote=%d" % [used, 1 if FileAccess.file_exists(WROTE_TO) else 0])
	quit()
