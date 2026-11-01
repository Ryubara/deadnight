class_name NightCommand
extends RefCounted
## Everything one player asks of the server in one tick: how to move (a `PlayerCommand`), whether
## the trigger is held, the camera ray and barrel the shot would leave from, and the three edges
## `reload`, `use` and `swap`. A human's controls and the autopilot both produce exactly this, and
## it travels as plain data (`to_dict`), so the server cannot tell them apart.

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
## Pressed this tick: take the next weapon carried in hand.
var swap := false
## The camera ray a shot follows, and where the barrel is.
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var muzzle := Vector3.ZERO


func to_dict() -> Dictionary:
	return {
		"type": NightServer.COMMAND,
		"player_id": player_id,
		"seq": seq,
		"motion": motion.to_dict(),
		"fire": fire,
		"reload": reload,
		"use": use,
		"swap": swap,
		"origin": origin,
		"dir": dir,
		"muzzle": muzzle,
	}


static func from_dict(data: Dictionary) -> NightCommand:
	var command := NightCommand.new()
	command.player_id = data.get("player_id", 1)
	command.seq = data.get("seq", 0)
	command.motion = PlayerCommand.from_dict(data.get("motion", {}))
	command.fire = data.get("fire", false)
	command.reload = data.get("reload", false)
	command.use = data.get("use", false)
	command.swap = data.get("swap", false)
	command.origin = data.get("origin", Vector3.ZERO)
	command.dir = data.get("dir", Vector3.FORWARD)
	command.muzzle = data.get("muzzle", Vector3.ZERO)
	return command
