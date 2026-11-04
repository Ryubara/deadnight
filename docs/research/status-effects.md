# Status effects and the wonder weapons

What the freeze gun and the ray gun (#788) taught us about putting a state on a zombie, so the re-cut elements
(#794) can reuse it. The design is [Weapons](../design/weapons.md#wonder-weapons-and-status-effects).

## Where the state lives

| Question | Answer | Why |
| --- | --- | --- |
| Who owns the seconds left? | `StatusBoard`, held by `CombatServer` | the weapon that puts a status on is the combat server's; the clock is its tick |
| Who reads it? | The rules (`GameRules.statuses`, the board itself, not a `Callable`), the night server (to tell the simulation) | a `Callable` to a method of a `RefCounted` held across objects crashed Godot at exit before (`ZombieSim.barricades`); the object is held instead |
| How does a client know? | The zombie's mode byte: mode in 3 bits, status in 3 more, the tearing bit on top | no new bytes, and the delta already sends the byte when it changes (`ZombieDelta`); protocol 13 to 14 because an old client would read the status bits as a mode |
| How does an event reach everyone? | `status_applied` and `status_ended` ride the combat events; `zombie_shattered` is the night server's | the shatter needs where the zombie stood, which only the simulation knew before it dropped the zombie |

## Things that bit

- **The freeze is a property of the zombie kind, not of the weapon or the round**: `ZombieType.freeze_bolts` (a brute 3)
  and `freezable` (bosses false) are data, and `StatusDef.kind_gated` says a status reads them. The bolts before the
  last only slow (`chilled`) and the count (`StatusBoard.add_bolt`) lives as long as the slow. #794's elements that do
  not depend on the kind leave `kind_gated` off.
- **A weapon's own hit must not break what it put on**: `RulesAction.hit`'s `keeps` names the status the hit spares, or
  the freeze gun's bolt (30 damage, a hit on the frozen zombie it just froze) would shatter its own target.
- **A zombie that came for a fence's breach is pushed back to its boards** (`ZombieSim._keep_outside_the_boards`)
  every step, so a test or a capture that places one in the open must clear its `gate_id`, or it is back at the
  fence a tick later.
- **A hit and a freeze in one shot** are ordered: the status goes on after the damage, and only to a zombie that is
  still alive, so the shot that freezes is never the one that shatters (the check is made before the damage).
- **Grenades do not pass the combat server**, so "any hit kills a frozen zombie" is in the rules (`_hit` and
  `ExplosionPlay._blast_one`), the one place every damage goes through.
- **The balance gate sees new weapons at once**: the crane's pool reaches the simulator, whose median round and time
  to kill are gated, and the roster's ray gun (300 and a blast of 160) alone took the average median round past its
  bound and the time to kill a walker to 0.36 s. The simulator does not model the freeze or the ray gun's hurt to its
  shooter, so `NightSim.UNMODELLED` leaves the two prizes out of its crane until they are modelled.
- **A capture needs a clear lane**: the lot is full of cars that block a shoulder camera's shot and hide a zombie.
  `tests/captures/wonder_weapons.gd` finds an open strip by dropping rays on a grid, then aims the view at the middle
  zombie.
- **A burning is a status plus a ticker the server owns** (#820): the board keeps the seconds (`burning`, wire 3, no
  halt, no slow), `CombatServer._burns` keeps whose it is and when the next hit falls, and the hit is an ordinary
  `_hurt`, so pay and kills are the rules'. Run the burn ticks **before** `statuses.step`, or the last tick of a 3 s
  burn lands after the status is gone and the total is 75, not 90. Never tick a frozen zombie (any hit shatters it).
- **"Not stacking" came free from the board**: `apply` keeps the longer time, so a second hit restarts it; one
  `element_burn` per hit lets the client restart its one flame (`ElementFx.restart`) instead of drawing two.
- **A flame on a pooled view must not outlive it**: the views are parked and reused, so the flames look the view up
  by zombie id every frame and free themselves when it is gone or dying, not when their seconds are up.
- **The plan's "one-bolt band by round" had no meaning once the freeze went by kind**: its re-cut is the bolts a kind
  needs (`freeze_bolts_less`), read in `_put_status`; a bloom wider is `burst_radius_multiplier`.
