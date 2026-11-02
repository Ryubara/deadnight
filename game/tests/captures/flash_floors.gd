class_name FlashFloors
extends RefCounted
## What a muzzle flash must show on the screen, from the probe's per-frame rows
## (`flash_probe.gd`, `tools/web_smoke/flash.py`), and the floors that decide it. The floors are
## in `flash_floors.json`, one file for the desktop probe, the browser probe and the unit test.

const PATH := "res://tests/captures/flash_floors.json"


## The numbers of one weapon's shot from its rows: frames the flash was seen on, its biggest size
## over those frames, and its brightest value.
static func summarise(rows: Array) -> Dictionary:
	var seen := 0
	var up := 0
	var height := 0.0
	var area := 0.0
	var peak := 0.0
	var rise := 0.0
	var hot := 0
	var light := 0
	var gain := 0.0
	var first := -1
	var last := -1
	for row: Dictionary in rows:
		if row.get("up", false):
			up += 1
		if row.get("quad_px", 0) > 0:
			seen += 1
			if first < 0:
				first = row["n"]
			last = row["n"]
		var screen_h: float = maxf(1.0, row.get("screen_h", 1.0))
		height = maxf(height, float(row.get("quad_h_seen", 0)) / screen_h)
		area = maxf(area, float(row.get("quad_px", 0)) / maxf(1.0, row.get("screen_px", 1.0)))
		peak = maxf(peak, row.get("peak", 0.0))
		rise = maxf(rise, row.get("mean_rise", 0.0))
		hot = maxi(hot, row.get("hot_px", 0))
		light = maxi(light, row.get("light_px", 0))
		gain = maxf(gain, row.get("screen_gain", 0.0))
	return {
		"frames_up": up,
		"frames_seen": seen,
		"first_frame": first,
		"last_frame": last,
		"height_pct": snappedf(height * 100.0, 0.01),
		"area_pct": snappedf(area * 100.0, 0.001),
		"peak_luma": snappedf(peak, 0.1),
		"mean_rise": snappedf(rise, 0.1),
		"hot_px": hot,
		"light_px": light,
		"screen_gain": snappedf(gain, 0.01),
	}


## What is wrong with a summary, as sentences (empty when the flash passes).
static func problems(summary: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var floors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for key: String in floors["min"]:
		if summary.has(key) and summary[key] < floors["min"][key]:
			found.append("%s %s is under the floor %s" % [key, summary[key], floors["min"][key]])
	for key: String in floors["max"]:
		if summary.has(key) and summary[key] > floors["max"][key]:
			found.append("%s %s is over the ceiling %s" % [key, summary[key], floors["max"][key]])
	return found


## A diagnostic: makes the flash's shader draw without the depth test, to see what the gun and the
## body hide.
static func draw_without_depth_test() -> void:
	var shader: Shader = load("res://gameplay/weapons/fx/flash_star.gdshader")
	shader.code = shader.code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,")
