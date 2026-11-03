# Every gun reloads in the real night (#383): the player's reload command makes the server start
# it, the weapon in the Soldier's hand plays its reload motion (#683) for its reload time, and the
# reload's steps sound, counted per weapon, all before the reload is over.
extends GdUnitTestSuite

const GUNS: Array[StringName] = [
	&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun", &"dual_pistols"
]
const STEP_SECONDS := 0.05


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	return night


func _give(night: Night, weapon_id: StringName) -> void:
	night.server.combat.apply(CombatAction.give_weapon(1, weapon_id))
	night.server.combat.apply(CombatAction.equip(1, weapon_id))
	NightFixture.run(night, 3)
	night.server.combat.state_of(1, weapon_id).ammo = 0


func test_every_gun_moves_and_sounds_its_reload_in_the_night() -> void:
	var night := await _start()
	var body := night.player()
	var animation := body.get_node("AnimationTree") as PlayerAnimation
	animation.set_process(false)
	var sounds := night.get_node("WeaponSounds") as WeaponSounds
	sounds.set_process(false)
	var heard: Array[StringName] = []
	sounds.play = func(id: StringName, _at: Variant, _db: float) -> void: heard.append(id)
	for weapon_id in GUNS:
		await _give(night, weapon_id)
		var seconds: float = WeaponCatalog.get_def(weapon_id).reload_time
		var motion := ReloadMotion.for_weapon(weapon_id)
		var wanted := 0
		for step: StringName in WeaponSounds.RELOAD[weapon_id]:
			wanted += motion.event_shares(step).size()
		heard.clear()
		var press := NightCommand.new()
		press.reload = true
		NightFixture.run(night, 1, press)
		NightFixture.run(night, 2)
		# The reload runs: its motion plays (frames drive the animation) and the steps sound.
		var deepest := 0.0
		var elapsed := 0.0
		while elapsed < seconds - 0.02:
			animation._process(STEP_SECONDS)
			sounds.schedule.advance(STEP_SECONDS)
			elapsed += STEP_SECONDS
			deepest = maxf(deepest, animation.reload_weight())
		(
			assert_float(deepest)
			. override_failure_message("%s: the reload did not play" % weapon_id)
			. is_greater(0.9)
		)
		var reloads := heard.filter(func(id: StringName) -> bool: return id.begins_with("reload_"))
		(
			assert_int(reloads.size())
			. override_failure_message("%s: %d reload steps heard" % [weapon_id, reloads.size()])
			. is_equal(wanted)
		)
		# Over: back up.
		for _i in 20:
			animation._process(STEP_SECONDS)
		assert_float(animation.reload_weight()).is_equal_approx(0.0, 0.001)
	night.queue_free()
