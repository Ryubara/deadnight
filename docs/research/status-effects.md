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

- **A zombie that came for a fence's breach is pushed back to its boards** (`ZombieSim._keep_outside_the_boards`)
  every step, so a test or a capture that places one in the open must clear its `gate_id`, or it is back at the
  fence a tick later.
- **A hit and a freeze in one shot** are ordered: the status goes on after the damage, and only to a zombie that is
  still alive, so the shot that freezes is never the one that shatters (the check is made before the damage).
- **Grenades do not pass the combat server**, so "any hit kills a frozen zombie" is in the rules (`_hit` and
  `ExplosionPlay._blast_one`), the one place every damage goes through.
- **The balance gate sees new weapons at once**: the crane's pool reaches the simulator, whose median round and time
  to kill are gated. The provisional numbers of a wonder weapon are chosen to keep the gate green until the roster
  research sets them.
- **A capture needs a clear lane**: the lot is full of cars that block a shoulder camera's shot and hide a zombie.
  `tests/captures/wonder_weapons.gd` finds an open strip by dropping rays on a grid, then aims the view at the middle
  zombie.
