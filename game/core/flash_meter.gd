class_name FlashMeter
extends RefCounted
## Measures what a muzzle flash does to the picture, on the screen, in the renderer the game is
## played in. It is for the probes (`tests/captures/flash_probe.gd` on the desktop,
## `FlashWebProbe` in the browser), never called in play.
##
## `measure` is called right after a frame is drawn. It reads the frame back, draws it again with
## only the flash's light, and once more with no flash, and compares the three: so the numbers are
## the flash's own pixels (the shape drawn by its quads) and its own wash of light, exactly, not a
## guess from colour. A frame drawn again ends in `RenderingServer.frame_post_draw` again, so the
## caller ignores that signal while `busy` is true.
##
## Brightness is the picture's luma (0.2126 R + 0.7152 G + 0.0722 B, of 255) as displayed, after
## the tonemap; sizes are in the picture's own pixels, whatever the window stretches to.

## A pixel counts as the flash's when its brightness rose by this much (of 255).
const SEEN_RISE := 16.0
## ... and as hot when it is also at least this bright.
const HOT_LUMA := 200.0
## The light's faint wash counts from this rise.
const WASH_RISE := 4.0
## The part of the picture read pixel by pixel: this many pixels round the muzzle.
const CROP := Vector2i(400, 260)
## The whole picture is compared at this size, for the flash's wash over the screen.
const GAIN_SIZE := Vector2i(160, 90)

## True while a frame is being drawn again for a measure.
static var busy := false

## The cropped picture with the flash and the whole one, of the last measure (for saving).
var crop: Image
var full: Image


## The row for the frame just drawn: whether a flash is up, where its quads and light are, and
## what they did to the picture. `flash` is null when none is up (the row says so only).
func measure(viewport: Viewport, flash: MuzzleFlash) -> Dictionary:
	busy = true
	var row := _measure(viewport, flash)
	busy = false
	return row


func _measure(viewport: Viewport, flash: MuzzleFlash) -> Dictionary:
	full = viewport.get_texture().get_image()
	full.convert(Image.FORMAT_RGBA8)
	var size := Vector2(full.get_size())
	# The camera speaks in the window's own units (1920 by 1080 stretched); the picture is in real
	# pixels. Every size below is in the picture's.
	var scale := size / Vector2(viewport.get_visible_rect().size)
	var row := {"up": flash != null, "screen_w": size.x, "screen_h": size.y}
	if flash == null:
		return row
	row["age"] = flash.age
	row["light"] = flash.light.visible
	var camera := viewport.get_camera_3d()
	var box := _screen_box(flash, camera)
	row["quad_w_px"] = box.size.x * scale.x
	row["quad_h_px"] = box.size.y * scale.y
	var muzzle := camera.unproject_position(flash.global_position) * scale
	row["muzzle_x"] = muzzle.x
	row["muzzle_y"] = muzzle.y
	var region := Rect2i(Vector2i(muzzle) - CROP / 2, CROP).intersection(
		Rect2i(Vector2i.ZERO, Vector2i(size))
	)
	crop = full.get_region(region)
	var states := _hide(flash, false)
	RenderingServer.force_draw(false)
	var light_only := _read(viewport)
	_hide(flash, true)
	RenderingServer.force_draw(false)
	var bare := _read(viewport)
	_restore(flash, states)
	RenderingServer.force_draw(false)
	var quads := _compare(crop, light_only.get_region(region))
	var wash := _compare(light_only.get_region(region), bare.get_region(region))
	row["quad_px"] = quads["seen"]
	row["hot_px"] = quads["hot"]
	row["peak"] = quads["peak"]
	row["mean_rise"] = quads["mean_rise"]
	row["quad_w_seen"] = quads["w"]
	row["quad_h_seen"] = quads["h"]
	# Where the flash's pixels are, against the muzzle (picture pixels).
	row["off_x"] = quads["cx"] + region.position.x - muzzle.x
	row["off_y"] = quads["cy"] + region.position.y - muzzle.y
	row["light_px"] = wash["wash"]
	row["light_rise"] = wash["wash_rise"]
	# The whole screen, flash and light together, against none: how far the picture as a whole
	# brightens (the flash must not blind).
	row["screen_gain"] = _mean_luma(full) - _mean_luma(bare)
	row["screen_px"] = size.x * size.y
	return row


func _read(viewport: Viewport) -> Image:
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _hide(flash: MuzzleFlash, everything: bool) -> Dictionary:
	var states := {"flash": flash.visible, "quads": [], "light": flash.light.visible}
	for quad in flash.quads:
		states["quads"].append(quad.visible)
		quad.visible = false
	if everything:
		flash.light.visible = false
	return states


func _restore(flash: MuzzleFlash, states: Dictionary) -> void:
	flash.visible = states["flash"]
	flash.light.visible = states["light"]
	for i in flash.quads.size():
		flash.quads[i].visible = states["quads"][i]


## The screen box of the quads together, in the window's units.
func _screen_box(flash: MuzzleFlash, camera: Camera3D) -> Rect2:
	var box := Rect2()
	var first := true
	var corners := [
		Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, 0.5, 0), Vector3(0.5, 0.5, 0)
	]
	for quad in flash.quads:
		if not quad.visible:
			continue
		for corner: Vector3 in corners:
			var point := camera.unproject_position(quad.global_transform * corner)
			if first:
				box = Rect2(point, Vector2.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box


## Mean luma of the whole picture, from a small copy of it.
func _mean_luma(image: Image) -> float:
	var small := image.duplicate() as Image
	small.resize(GAIN_SIZE.x, GAIN_SIZE.y, Image.INTERPOLATE_BILINEAR)
	var data := small.get_data()
	var sum := 0.0
	var count := data.size() / 4
	for i in count:
		var o := i * 4
		sum += 0.2126 * data[o] + 0.7152 * data[o + 1] + 0.0722 * data[o + 2]
	return sum / maxf(1.0, float(count))


## How `after` differs from `before` (both RGBA8, the same size): the pixels that got brighter by
## at least `SEEN_RISE`, the hot ones, the brightest, the mean rise of the seen ones, their middle
## and the box they fill; and the pixels brighter by at least `WASH_RISE` and their mean rise.
func _compare(after: Image, before: Image) -> Dictionary:
	var a := after.get_data()
	var b := before.get_data()
	var seen := 0
	var wash := 0
	var hot := 0
	var peak := 0.0
	var sum := 0.0
	var wash_sum := 0.0
	var sum_x := 0.0
	var sum_y := 0.0
	var x0 := 100000
	var y0 := 100000
	var x1 := -1
	var y1 := -1
	var width := after.get_width()
	for i in a.size() / 4:
		var o := i * 4
		var la := 0.2126 * a[o] + 0.7152 * a[o + 1] + 0.0722 * a[o + 2]
		var lb := 0.2126 * b[o] + 0.7152 * b[o + 1] + 0.0722 * b[o + 2]
		var rise := la - lb
		if rise < WASH_RISE:
			continue
		wash += 1
		wash_sum += rise
		if rise < SEEN_RISE:
			continue
		seen += 1
		sum += rise
		peak = maxf(peak, la)
		if la >= HOT_LUMA:
			hot += 1
		var x := i % width
		var y := i / width
		sum_x += x
		sum_y += y
		x0 = mini(x0, x)
		x1 = maxi(x1, x)
		y0 = mini(y0, y)
		y1 = maxi(y1, y)
	return {
		"seen": seen,
		"wash": wash,
		"hot": hot,
		"peak": peak,
		"mean_rise": sum / maxf(1.0, float(seen)),
		"wash_rise": wash_sum / maxf(1.0, float(wash)),
		"cx": sum_x / maxf(1.0, float(seen)),
		"cy": sum_y / maxf(1.0, float(seen)),
		"w": (x1 - x0 + 1) if x1 >= 0 else 0,
		"h": (y1 - y0 + 1) if y1 >= 0 else 0,
	}
