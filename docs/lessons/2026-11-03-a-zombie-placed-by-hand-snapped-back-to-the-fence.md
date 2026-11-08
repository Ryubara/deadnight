# A zombie placed by hand in a test or a capture snapped back to the fence

2026-11-03

- **Symptom:** a capture of the freeze gun showed an empty lot: three zombies had been moved in front of the player
  (`body.position = ...`) and were nowhere to be seen a second later, though the server's hits on them counted.
- **Cause:** a zombie that spawned for a fence breach keeps its `gate_id` until it walks through; while boards stand,
  `ZombieSim._keep_outside_the_boards` puts it back at the boards every step. Moving it by hand changes nothing for
  long. The unit tests did not show it because they placed the zombie and asserted within a few ticks.
- **Fix:** clear `gate_id` (`body.gate_id = &""`) on a zombie a test or a capture puts in the open (the shared
  `drop_zombie` does), and stand it still with `speed = 0.0`. Find a lane for a shoulder camera by dropping rays on a
  grid: the lot's cars block the shot and hide a zombie that is only 6 m away. The general rule (a body placed by hand
  gets all of its state) is on the kit's [Testing a game](https://ryubara.github.io/gdstudio/gamedev/testing/#scenarios)
  page.
- **Documented:** [Status effects](../research/status-effects.md) ("Things that bit").
