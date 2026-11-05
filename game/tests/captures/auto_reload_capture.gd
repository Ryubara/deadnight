extends Node
## A phone aiming with auto-fire until the gun runs dry and reloads by itself (Deadnight #1278): the
## real `NightScreen` with the touch layer up, Aim held (a finger on it), a zombie held on the
## crosshair, the trigger never touched. The pistol is loaded with `--rounds` (3 by default) so the
## magazine runs out in the first second. Prints `CAPTURE <frame> ammo reserve reloading` for every
## frame, so the contact sheet can be read against the numbers. Not part of the game. Run it through
## the no-focus launcher with Movie Maker, a phone-sized window:
##
## `gds godot -- --path game res://tests/captures/auto_reload_capture.tscn --write-movie <abs>/f.png
##  --fixed-fps 10 --resolution 844x390 --quit-after 70 -- --rounds=3`

const PLAY := "res://ui/screens/play_screen.tscn"
const SETTINGS_PATH := "user://auto_reload_capture.cfg"
const PLAYER := 1
## How far down the view the zombie stands.
const REACH := 6.0
## Frames recorded once the fight starts, then the capture ends.
const AFTER_FRAMES := 50
## A hard stop whatever the run is waiting for (frames of the process clock): a capture that never
## reaches its fight must not fill the disk with frames.
const HARD_STOP_FRAMES := 900

var _screen: NightScreen
var _frame := 0
var _rounds := 3
var _fighting := false
var _alive := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rounds="):
			_rounds = int(argument.trim_prefix("--rounds="))
	_run.call_deferred()


func _run() -> void:
	TouchMode.device_is_touch = true
	UIInputMode.touch = true
	Settings.path = SETTINGS_PATH
	Settings.reset_defaults()
	Settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 255)
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = 0
	chosen.break_seconds = 1.0
	UIRouter.reset(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	var play := UIRouter.top() as PlayScreen
	play.panel.set_settings(chosen.clamped())
	play.start()
	await UIRouter.idle
	_screen = UIRouter.top() as NightScreen
	await _screen.night.ready_to_play
	var night := _screen.night
	print("CAPTURE ready_to_play, arriving ", night.is_arriving())
	if night.is_arriving():
		# `skip_now` ends the show at once and emits `arrival_ended` inside the call: awaiting the
		# signal afterwards waits for one that has gone by, for ever (the first run of this capture).
		night.arrival_show.skip_now()
	var show_node: Node = night.arrival_show
	for _i in 600:
		if not is_instance_valid(show_node):
			break
		await get_tree().physics_frame
	print("CAPTURE arrival over")
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	for _i in 600:
		await get_tree().physics_frame
		if not night.server.sim.zombies.is_empty():
			break
	night.server.combat.weapon_of(PLAYER).ammo = _rounds
	Input.action_press(&"aim")
	_fighting = true
	print("CAPTURE ready, pistol ", night.server.combat.weapon_of(PLAYER).def.id)


func _process(_delta: float) -> void:
	_alive += 1
	if _alive >= HARD_STOP_FRAMES:
		print("CAPTURE hard stop, fighting ", _fighting)
		get_tree().quit()
		return
	if _screen == null or _screen.night.server == null or not _fighting:
		return
	var night := _screen.night
	var view := night.player().camera_rig.aim_transform()
	for zombie: ZombieBody in night.server.sim.zombies.values():
		zombie.position = view.origin + (-view.basis.z) * REACH - Vector3.UP * 1.2
		zombie.velocity = Vector3.ZERO
		break
	var held := night.server.combat.weapon_of(PLAYER)
	if held != null:
		_frame += 1
		print("CAPTURE ", _frame, " ", held.ammo, " ", held.reserve, " ", held.is_reloading())
		if _frame >= AFTER_FRAMES:
			get_tree().quit()
