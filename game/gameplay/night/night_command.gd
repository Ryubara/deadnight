class_name NightCommand
extends RefCounted
## Everything one player asks of the server in one tick: how to move (a `PlayerCommand`), whether
## the trigger and the use button are held, the camera ray and barrel the shot would leave from,
## and the three edges `reload`, `use` and `swap`. A human's controls and the autopilot both produce
## exactly this, and it travels as plain data (`to_dict`), so the server cannot tell them apart.

var player_id := 1
## The client's own count of its commands (one per tick); the server hands it back in the frame
## (`ack`) so a predicting client knows how far the server has got.
var seq := 0
var motion := PlayerCommand.new()
var fire := false
## Pressed this tick: start a reload.
var reload := false
## Pressed this tick: buy what is in reach (a door), else put a board back.
var use := false
## Down this tick (the level, not the edge): a press that began at a breach goes on putting boards
## back, one every `NightTuning.repair_interval`, for as long as this stays true.
var use_held := false
## Pressed this tick: take the next weapon carried in hand.
var swap := false
## The camera ray a shot follows, and where the barrel is.
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var muzzle := Vector3.ZERO
## The server step of the newest frame the shooter had when this command was made (its low 16 bits
## travel), which is the world the shot was aimed at: the server judges the shot against the dead
## where they were then (`LagCompensator`). -1 when the sender does not say (the shot is judged
## against the present, as in single-player).
var view_step := -1
## Set by the server on arrival when `view_step` is: the whole server step it means (see
## `NightServer.submit`); may be negative early in a night, for a view older than the night.
var view_tick := 0


func to_dict() -> Dictionary:
	return {
		"type": NightServer.COMMAND,
		"player_id": player_id,
		"seq": seq,
		"motion": motion.to_dict(),
		"fire": fire,
		"reload": reload,
		"use": use,
		"use_held": use_held,
		"swap": swap,
		"origin": origin,
		"dir": dir,
		"muzzle": muzzle,
		"view_step": view_step,
	}


static func from_dict(data: Dictionary) -> NightCommand:
	var command := NightCommand.new()
	command.player_id = data.get("player_id", 1)
	command.seq = data.get("seq", 0)
	command.motion = PlayerCommand.from_dict(data.get("motion", {}))
	command.fire = data.get("fire", false)
	command.reload = data.get("reload", false)
	command.use = data.get("use", false)
	command.use_held = data.get("use_held", false)
	command.swap = data.get("swap", false)
	command.origin = data.get("origin", Vector3.ZERO)
	command.dir = data.get("dir", Vector3.FORWARD)
	command.muzzle = data.get("muzzle", Vector3.ZERO)
	command.view_step = data.get("view_step", -1)
	return command
