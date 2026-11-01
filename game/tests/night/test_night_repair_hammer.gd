# The hammer in the hand while repairing: holding use at a broken breach puts the held weapon away
# and shows the claw hammer on the right-hand mount; letting go brings the weapon back. Driven like
# the hold suite (commands through the link, the rules' events back); the animation is stepped by
# hand with the night, a tick at a time, so nothing waits on the clock.
extends GdUnitTestSuite

const BREACH := &"nw"
const SETTLE := 30
const TEAR_ALL := 5
## Ticks that carry the Equip clip past its weapon_visible frame.
const EQUIP_TICKS := 60


func _start() -> Night:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 60.0
	tuning.rounds.first_spawn_delay = 600.0
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, SETTLE)
	# The starting pistol has no model yet (docs/design/weapon-hold.md), so a rifle is put in the hand:
	# the hammer takes the place of a weapon that is shown.
	night.server.combat.apply(CombatAction.give_weapon(Night.PLAYER_ID, &"rifle"))
	night.server.combat.apply(CombatAction.equip(Night.PLAYER_ID, &"rifle"))
	NightFixture.run(night, 3)
	# The Equip clip shows the rifle on its weapon_visible frame: step the animation through it.
	var animation := _animation(night)
	for _i in EQUIP_TICKS:
		animation._process(NightFixture.STEP)
	for _i in TEAR_ALL:
		night.server.rules.barricades.tear(BREACH)
	night.world.barricade(BREACH).set_boards(night.server.rules.barricades.boards_of(BREACH))
	night.player().teleport(night.world.repair_spot(BREACH))
	NightFixture.run(night, 2)
	_animation(night).set_process(false)
	return night


func _animation(night: Night) -> PlayerAnimation:
	return night.player().get_node(^"AnimationTree") as PlayerAnimation


## `ticks` ticks of the night and of the player's animation; the button down when `held`, and the
## first tick the press itself when `press`.
func _run(night: Night, ticks: int, held: bool, press := false) -> void:
	var animation := _animation(night)
	for i in ticks:
		var command := NightCommand.new()
		command.use = press and i == 0
		command.use_held = held
		NightFixture.run(night, 1, command)
		animation._process(NightFixture.STEP)


func test_the_hammer_waits_hidden_on_the_hand_mount() -> void:
	var night := await _start()
	var animation := _animation(night)
	assert_object(animation.hammer()).is_not_null()
	assert_object(animation.hammer().get_parent()).is_same(animation.weapon_mount())
	assert_str(animation.weapon_mount().bone_name).is_equal(PlayerAnimation.HAND_BONE)
	assert_bool(animation.hammer().visible).is_false()
	assert_bool(animation.weapon().visible).is_true()
	night.queue_free()


func test_holding_repair_shows_the_hammer_and_letting_go_brings_the_weapon_back() -> void:
	var night := await _start()
	var animation := _animation(night)
	var interval := night.server.tuning.repair_interval
	_run(night, 3, true, true)
	assert_int(night.server.rules.barricades.boards_of(BREACH)).is_equal(1)
	assert_bool(animation.is_repairing()).is_true()
	assert_bool(animation.hammer().visible).is_true()
	assert_bool(animation.weapon().visible).is_false()
	# Board after board, the hammer stays in the hand.
	_run(night, roundi(interval * 60.0 * 2.0), true)
	assert_int(night.server.rules.barricades.boards_of(BREACH)).is_equal(3)
	assert_bool(animation.hammer().visible).is_true()
	assert_bool(animation.weapon().visible).is_false()
	# Let go: no board follows, the clip lets go after 1.5 intervals and the weapon is back.
	_run(night, roundi(interval * 60.0 * (PlayerAnimation.REPAIR_HOLD + 0.2)), false)
	assert_int(night.server.rules.barricades.boards_of(BREACH)).is_equal(3)
	assert_bool(animation.is_repairing()).is_false()
	assert_bool(animation.hammer().visible).is_false()
	assert_bool(animation.weapon().visible).is_true()
	night.queue_free()
