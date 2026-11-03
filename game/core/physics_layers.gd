class_name PhysicsLayers
extends RefCounted
## The physics layers of the night, as the bits a mask lists.
##
## A played body is on `BODY` and no body's mask lists it, so bodies never block one another: on a
## client the other players are drawings that stop nobody, and the server's must agree or a sprint
## into a teammate ends metres apart (#760). A ray that must still meet a body (a shot, the dead's
## swing, a grenade, a ping) lists `BODY` in its own mask.

## Walls, props, doors and floors: what a body and a shot are stopped by.
const WORLD := 1
## Boards across a breach, and the windows' blockers: bodies are stopped by them, shots are not.
const BOARDS := 2
## A played body (the server's, and the one a client predicts).
const BODY := 4
