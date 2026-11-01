class_name MpEntity
extends Node
## One replicated thing (a player or a zombie) on the built-in MultiplayerAPI: two plain
## properties and a
## MultiplayerSynchronizer that the engine sends to every peer when they change.

signal updated

## Set once at start-up from the command line, on the server and on every client alike.
static var packed := false  # send the position as one int32 (two i16) instead of a Vector2i variant
# Players' synchronizers owned by their clients (the dropped first design).
static var client_auth := false

var id := 0
var owner_peer := 0  # the peer that drives it; 0 for a zombie
var wire := 0  # the position as the packed int, what actually travels when `packed`
var sim_pos := Vector2i.ZERO:
	get:
		return _unpack(wire) if packed else sim_pos
	set(value):
		sim_pos = value
		wire = (value.x << 16) | (value.y & 0xFFFF)  # fits an int32: the variant encoder sends 4 bytes
var ack_seq := 0  # the newest input this player's owner sent that the server applied


func setup(spawn_data: Array) -> void:
	id = spawn_data[0]
	owner_peer = spawn_data[1]
	name = "e%d" % id
	var config := SceneReplicationConfig.new()
	for property in _synced_properties():
		var path := NodePath(":" + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(
			path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_config = config
	synchronizer.replication_interval = 1.0 / GameSim.TICK_RATE
	# ON_CHANGE properties arrive as a delta sync, ALWAYS ones as a full sync: listen to both.
	synchronizer.synchronized.connect(func() -> void: updated.emit())
	synchronizer.delta_synchronized.connect(func() -> void: updated.emit())
	if client_auth and not is_zombie():
		synchronizer.set_multiplayer_authority(owner_peer)
	add_child(synchronizer)


func is_zombie() -> bool:
	return owner_peer == 0


func _synced_properties() -> PackedStringArray:
	var position_property := "wire" if packed else "sim_pos"
	return [position_property] if is_zombie() else [position_property, "ack_seq"]


static func _unpack(packed_value: int) -> Vector2i:
	var y := packed_value & 0xFFFF
	return Vector2i(packed_value >> 16, y - 0x10000 if y >= 0x8000 else y)
