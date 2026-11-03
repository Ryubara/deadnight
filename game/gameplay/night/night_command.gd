class_name NightCommand
extends RefCounted
## Everything one player asks of the server in one tick: how to move (a `PlayerCommand`), whether
## the trigger and the use button are held, the camera ray and barrel the shot would leave from,
## and the edges `reload`, `use`, `swap` and `slot`. A human's controls and the autopilot both
## produce exactly this, and it travels as plain data (`to_dict`), so the server cannot tell them
## apart.

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
## Pressed this tick: take the weapon in this slot in hand (1 is the first weapon carried, see
## `WeaponSlots`), 0 for no slot.
var slot := WeaponSlots.NONE
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


## Looks along `direction` and shoots along it: the view turn (`motion.yaw` and `pitch`) and the
## shot's `dir` agree, as a person's always do. The server refuses a shot that disagrees with its
## view (`NightServer.aims_with_view`), so a command that wants to fire somewhere sets it this way.
func aim_along(direction: Vector3) -> void:
	dir = direction.normalized()
	motion.yaw = atan2(-dir.x, -dir.z)
	motion.pitch = asin(clampf(dir.y, -1.0, 1.0))


## The other way round: the view turn is (`yaw`, `pitch`) and the shot's `dir` is derived from it,
## the camera's forward (the basis of `NightServer.view_dir`). A client that turns its view with a
## model of its own (a spring, a turn-rate cap) sets the view and gets a shot that agrees with it.
func look_along(yaw: float, pitch: float) -> void:
	motion.yaw = yaw
	motion.pitch = pitch
	dir = Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Keeps the pressed edges (`reload`, `use`, `swap`, `slot`) of the command this one replaces that
## no step has used yet.
func inherit_edges(old: NightCommand) -> void:
	reload = reload or old.reload
	use = use or old.use
	swap = swap or old.swap
	if slot == WeaponSlots.NONE:
		slot = old.slot


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
		"slot": slot,
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
	command.slot = data.get("slot", WeaponSlots.NONE)
	command.origin = data.get("origin", Vector3.ZERO)
	command.dir = data.get("dir", Vector3.FORWARD)
	command.muzzle = data.get("muzzle", Vector3.ZERO)
	command.view_step = data.get("view_step", -1)
	return command
