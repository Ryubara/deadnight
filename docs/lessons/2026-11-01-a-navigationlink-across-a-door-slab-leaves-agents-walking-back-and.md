# A NavigationLink across a door slab leaves agents walking back and forth on it

2026-11-01

- **Symptom:** Zombies reached the link in front of an opened door and then stood there, moving a few centimetres to
  and fro for as long as the run lasted, although the link was enabled and `map_get_path` crossed it.
- **Cause:** A mesh baked with the slab present has a band without mesh round it (the slab plus the agent radius each
  side, 1.3 m). A link only spans the band; an agent inside the band is off the mesh, so each repath snaps it to the
  nearer edge and the new path starts there, back at the link's start. At 3 m/s and a 0.25 s repath the agent covers
  0.75 m, less than the band's far half.
- **Fix:** Do not bridge a baked wall with a link for agents that repath often. Rebake the mesh when the door opens
  (`bake_from_source_geometry_data_async`, a worker thread, about a second for the lot) and swap it into the region;
  or keep the path across a link and do not repath while an agent is on it.
- **Documented:** Deadnight `docs/research/zombies.md#doors`.
