extends GdUnitTestSuite
## The grenade sounds: the four ids exist, load, have the shape their job needs (a short tick, a
## bounce, a throw, a blast with a tail) and the service plays each on a pooled player.

const IDS: Array[StringName] = [
	&"grenade_tick", &"grenade_throw", &"grenade_bounce", &"grenade_blast"
]
## Seconds a variant may last: [shortest, longest].
const LENGTHS := {
	&"grenade_tick": [0.01, 0.15],
	&"grenade_throw": [0.15, 0.7],
	&"grenade_bounce": [0.04, 0.4],
	&"grenade_blast": [0.8, 3.0],
}

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(3)
	add_child(_audio)


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func test_every_variant_loads_and_has_the_length_of_its_job() -> void:
	for id in IDS:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message(String(id)).is_not_null()
		for variant in range(1, def.variants + 1):
			var stream := load(def.path_for(variant)) as AudioStreamOggVorbis
			assert_object(stream).is_not_null()
			var span: Array = LENGTHS[id]
			assert_float(stream.get_length()).is_between(span[0], span[1])


func test_each_plays_on_a_pooled_player_near_the_listener() -> void:
	for id in IDS:
		var player := _audio.play(id, Vector3(2, 1, -3))
		assert_object(player).override_failure_message(String(id)).is_not_null()


func test_the_blast_carries_further_than_the_tick() -> void:
	var tick := SoundCatalog.get_def(&"grenade_tick")
	var blast := SoundCatalog.get_def(&"grenade_blast")
	assert_float(blast.max_distance).is_greater(tick.max_distance * 2.0)
	assert_int(blast.priority).is_greater(tick.priority)
