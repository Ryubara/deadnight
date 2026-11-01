extends Node


func _ready() -> void:
	var log := []
	var total_us := 0
	for id in SoundCatalog.ids():
		var t0 := Time.get_ticks_usec()
		Audio.preload_sound(id)
		var us := Time.get_ticks_usec() - t0
		total_us += us
		log.append([String(id), us])
		if OS.has_feature("web"):
			JavaScriptBridge.get_interface("window").deadnightAudioLast = String(id)
	var json := JSON.stringify({"total_us": total_us, "log": log})
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").deadnightAudioTest = json
	else:
		print(json.substr(0, 400))
		get_tree().quit()
