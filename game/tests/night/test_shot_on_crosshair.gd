# A shot lands on the crosshair (#601): the maintainer played the web build on an iPhone and the
# bullets did not land where the crosshair was. This fires the real shot (the trigger, the night's
# tick, the server) at a wall square across the centre of the screen, close, at mid range and far,
# from the hip and aimed, with a mouse and with a finger on the touch layer, on a desktop canvas and
# on the phone's 540 unit canvas, and asserts the shot's end is drawn on the reticle.
extends GdUnitTestSuite

## How far (canvas units) the end of a shot may be drawn from the reticle's centre: well under the
## reticle's own gap, so a player sees the shot land on the dot.
const TOLERANCE := 1.5
## A head is a big ball and the muzzle's ray, a shoulder to the side of the camera's, meets its
## surface a little to the side of where the camera's does: a head on the dot is allowed more.
const HEAD_TOLERANCE := 3.0
const DISTANCES: Array[float] = [4.0, 10.0, 22.0]
const DESKTOP := Vector2i(1920, 1080)
## A phone held sideways: the canvas is 540 units high there (`MenuScale`).
const PHONE := Vector2i(844, 390)

var _rig: ShotRig
var _window := Vector2i.ZERO
var _scale := 1.0
var _zones_wanted := false


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_zones_wanted = false
	_window = get_tree().root.size
	_scale = get_tree().root.content_scale_factor


func after_test() -> void:
	if _rig != null:
		_rig.free_all()
		_rig = null
	get_tree().root.size = _window
	get_tree().root.content_scale_factor = _scale
	await RouterFixture.clear(get_tree())
	Audio.stop_all()


func _canvas(size: Vector2i) -> void:
	get_tree().root.size = size
	get_tree().root.content_scale_factor = MenuScale.factor(size, 1.0)


## A night screen entered the way the menu's Solo does, with a touch layer when `touch`, stepped by
## this suite.
func _enter(touch: bool) -> ShotRig:
	TouchMode.device_is_touch = touch
	UIInputMode.touch = touch
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push("res://ui/screens/night_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	screen.night.ticks_per_frame = 0
	var fingers: TouchFixture = null
	if touch:
		var controls := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
		fingers = TouchFixture.attach(self, controls)
	var rig := ShotRig.attach(self, screen, touch, fingers)
	await rig.frames(2)
	return rig


## Every distance, from the hip and aimed: the numbers `off` of each shot, named for the failure.
func _sweep(touch: bool, size: Vector2i, insets := Vector4.ZERO, at_head := false) -> Dictionary:
	get_tree().root.size = size
	_rig = await _enter(touch)
	_canvas(size)
	await _rig.frames(2)
	if insets != Vector4.ZERO:
		_rig.safe_area(insets)
		await _rig.frames(2)
	_rig.spread_off()
	assert_bool(_rig.face_open_ground(DISTANCES.max() + 6.0)).is_true()
	await _rig.frames(40)
	if at_head:
		assert_bool(_rig.call_zombie()).is_true()
	var found := {}
	for aimed in [false, true]:
		for metres in DISTANCES:
			await _rig.aim(aimed)
			await _rig.frames(40)
			if at_head:
				_rig.head_on_crosshair(metres)
			else:
				_rig.wall_at(metres)
			await _rig.settle_wall()
			var shot := await _rig.shoot()
			var key := "%s %.0f m" % ["aimed" if aimed else "hip", metres]
			found[key] = shot
			await _rig.aim(false)
			await _rig.frames(20)
	return found


func _assert_on_the_dot(found: Dictionary) -> void:
	print("SHOTS ", found, " canvas ", get_viewport().get_visible_rect().size)
	for key: String in found:
		var off: float = found[key].get("off", INF)
		if _zones_wanted:
			(
				assert_array(found[key].get("zones", []))
				. override_failure_message(
					(
						"%s: a zombie's head on the dot took %s (the shot is %s units off)"
						% [key, found[key].get("zones"), off]
					)
				)
				. contains([&"head"])
			)
		(
			assert_float(off)
			. override_failure_message(
				"%s: the shot is drawn %s units off the reticle (%s)" % [key, off, found[key]]
			)
			. is_less(HEAD_TOLERANCE if _zones_wanted else TOLERANCE)
		)


func test_a_mouse_shot_lands_on_the_crosshair_on_a_desktop() -> void:
	_assert_on_the_dot(await _sweep(false, DESKTOP))


func test_a_mouse_shot_lands_on_the_crosshair_on_the_phone_canvas() -> void:
	_assert_on_the_dot(await _sweep(false, PHONE))


func test_a_touch_shot_lands_on_the_crosshair_on_a_desktop() -> void:
	_assert_on_the_dot(await _sweep(true, DESKTOP))


func test_a_touch_shot_lands_on_the_crosshair_on_the_phone_canvas() -> void:
	_assert_on_the_dot(await _sweep(true, PHONE))


## An iPhone held sideways, in the page's CSS pixels: the notch side, none at the top, the home bar
## under the picture. The touch layer scales them to the canvas (844 CSS pixels across).
func test_a_touch_shot_lands_on_the_crosshair_with_the_iphone_safe_area() -> void:
	var k := 1168.5 / 844.0
	_assert_on_the_dot(await _sweep(true, PHONE, Vector4(59.0, 0.0, 59.0, 21.0) * k))


## What the player sees as hitting: a zombie's head (a 22 cm ball) on the dot takes a headshot, at
## every range, with a finger, behind the same safe area.
func test_a_zombie_head_on_the_dot_takes_the_headshot_with_a_finger_on_an_iphone() -> void:
	_zones_wanted = true
	var k := 1168.5 / 844.0
	_assert_on_the_dot(await _sweep(true, PHONE, Vector4(59.0, 0.0, 59.0, 21.0) * k, true))


func test_a_zombie_head_on_the_dot_takes_the_headshot_with_the_mouse() -> void:
	_zones_wanted = true
	_assert_on_the_dot(await _sweep(false, DESKTOP, Vector4.ZERO, true))


## A notch on one side only (an Android phone): the cards are inset on the left, not the right.
func test_a_touch_shot_lands_on_the_crosshair_with_a_notch_on_one_side() -> void:
	_assert_on_the_dot(await _sweep(true, PHONE, Vector4(66.0, 0.0, 0.0, 0.0)))
