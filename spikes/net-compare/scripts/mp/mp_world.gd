class_name MpWorld
extends Node
## What the server and every client share: the container the spawner fills, the spawn function,
## and the
## few RPCs. Both sides build it at the same node path, which is what the MultiplayerAPI requires.

signal entity_spawned(entity: MpEntity)
signal input_received(peer: int, seq: int, dir: Vector2i)
signal pong_received(client_tick: int)

var entities := Node.new()
var _spawner := MultiplayerSpawner.new()


func _ready() -> void:
	entities.name = "Entities"
	add_child(entities)
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("../Entities")
	_spawner.spawn_function = _spawn
	add_child(_spawner)
	entities.child_entered_tree.connect(func(node: Node) -> void: entity_spawned.emit(node))


## Server only. `spawn_data` is [id, owner_peer].
func spawn_entity(spawn_data: Array) -> MpEntity:
	return _spawner.spawn(spawn_data) as MpEntity


func _spawn(spawn_data: Array) -> Node:
	var entity := MpEntity.new()
	entity.setup(spawn_data)
	return entity


## `call_local` so that single-player (an OfflineMultiplayerPeer, no remote side) runs it too.
@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_input(seq: int, dir: Vector2i) -> void:
	var sender := multiplayer.get_remote_sender_id()
	input_received.emit(sender if sender != 0 else multiplayer.get_unique_id(), seq, dir)


@rpc("any_peer", "call_remote", "reliable")
func ping(client_tick: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), client_tick)


@rpc("authority", "call_remote", "reliable")
func pong(client_tick: int) -> void:
	pong_received.emit(client_tick)
