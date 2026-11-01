# gds_ui

Tokens, a generated theme, drawn components, motion and a screen router. The decisions behind it, with the
measurements, are in the game's `docs/research/ui-foundation.md`.

## Adding a router transition

A transition is a `UITransition` whose `play(ctx)` is awaited by the router. Before it merges, check each item and
attach the captures to the pull request.

1. **Push and pop, both captured.** `demo/transition_tour.tscn` walks every kind with the keyboard (Enter pushes, Esc
   pops); capture it with Movie Maker at 10 fps and look at the frames of the pop, not only the push. A pop must
   mirror the push, with the leaving screen on top where the push had the entering one on top.
2. **Layering is explicit.** Call `ctx.raise(screen)` for the screen that must be on top; never rely on the stage's
   child order.
3. **Tweens belong to the stage.** Create them on `ctx.stage`, or with `UIMotion.fade_in(control, delay, owner)` and the
   stage as `owner`; never on a screen. A tween on a freed screen never emits `finished`, and the router waits forever.
4. **Check `is_instance_valid` after every await**, through `ctx.has_outgoing()` and `ctx.swap()`. Add the case to
   `tests/ui/test_ui_router.gd` next to the existing ones: the outgoing, the incoming and the popped screen freed
   mid-transition must each leave `busy` false and the stack right.
5. **The queue drains.** Push, pop and replace queued during the transition run in order (`test_queued_calls_*`).
6. **Reduced motion snaps.** With `UIMotion.reduced` nothing moves: the router swaps the slide, burn and iris for the
   fade (`UIRouter._make`).
7. **Compatibility renderer.** A shader transition does not sample the screen (`hint_screen_texture` needs a back-buffer
   copy); the colour behind the fade is the token `bg`, set as the default clear colour by the router.
8. **A paused screen still animates.** The router restores a screen's `process_mode` before the transition; do not
   create tweens on a node whose mode is disabled.

## Animating the children of a container

`UIMotion.stagger_in` tweens `position`, which a container owns. It waits until the container has sorted (two
`process_frame`s: the sort is a deferred call that runs after the signal, and an input event is handled before it in
the same frame), stops an earlier rise of the same control, and asks the container to sort again when the rise ends.
Do the same for any tween of a container child's position: never read `position` in the frame the child was shown.
