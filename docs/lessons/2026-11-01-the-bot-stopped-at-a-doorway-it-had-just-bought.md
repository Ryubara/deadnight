# The bot stopped at a doorway it had just bought

2026-11-01

- **Symptom:** a night test bought the concession for the autopilot and the bot stood outside the stand for a minute,
  its path ending at the wall; the same bot reached a breaker post outside the stand without trouble (#247).
- **Cause:** the new navigation mesh is baked on a worker thread and the server takes it a few physics frames later;
  `night.tick()` does not step the server, and waiting for the bake to end is not waiting for the map.
- **Fix:** after `NightFixture.settle_bake`, await a few `physics_frame`s before sending the bot somewhere through the door.
- **Documented:** [greybox and captures](../research/greybox-and-captures.md#the-fuel-cans).
