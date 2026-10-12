# dot-spectate design

Why the addon is shaped the way it is, and why the obvious alternative is wrong at each point. The rules are one line each in [CLAUDE.md](../CLAUDE.md).

## Spectating is a competitive-integrity system before it is a camera

The camera is about four lines of vector arithmetic. Everything else here exists because somebody used a spectator view to cheat:

- a dead player calling out positions to the living;
- a streamer whose viewers read the map for them;
- a team-mate on a second machine, watching the other side.

The two features that matter are the force-camera policy and the delay, and both live on the server, because a client that decides what it may look at is a client that may look at anything.

## It computes a transform and never touches a camera

`camera_of(key)` returns a `Transform3D`. `camera_2d_of(key)` returns a position and an angle for a game on the XZ plane. A game assigns it to its own rig. Same rule as dot-ui's "ships no art", and it is what lets one manager serve a 3D shooter's `Camera3D`, a 2D arena's `Camera2D` and a headless suite with no camera at all: three deployment shapes, no second code path.

## The genre's seven modes, and its numbering

`DotSpectatorView.Mode`: `NONE`, `DEATH_CAM`, `FREEZE_CAM`, `FIXED`, `FIRST_PERSON`, `CHASE`, `ROAMING`. Kept because twenty years of tooling, demo formats and server documentation say exactly this. `DotSpectatorRules.force_camera` (0 anybody, 1 own team only, 2 nobody) uses the numbering server operators already type from memory.

"Own team only" also means first person: a chase camera behind a team-mate sees round corners that team-mate cannot. `_permitted_mode()` downgrades a request rather than refusing it, and says so in the log: a player who pressed a key and got a different camera with no explanation reports it as a broken control.

## The delay is why there is a history at all

A spectator watching live is a live intelligence feed. A broadcast relay's answer is ninety seconds and a competitive server's is a few; either way the camera samples a tick in the past (`delay_ticks`) and nothing else in the addon has to know that it did.

The ring (`DotSpectatorHistory`) is bounded, and the bound is validated against the delay. A history that grows with the round is a memory leak with a plausible name ([history](history.md#a-bound-nothing-read)).

A sample with no history reports not-found: `DotSpectatorHistory.sample` returns `[Transform3D, found]`. Returning `Transform3D.IDENTITY` alone would put a camera at the world origin looking down the X axis, which is indistinguishable from a camera that is working and a world that has vanished.

## The death-cam chain hands over

`on_death` then death cam, freeze cam, a real target. Three timers that have to hand over to each other, and every game that writes it itself gets the last hand-over wrong: the freeze camera ends, nothing takes over, and the player sits looking at their killer until they respawn.

With nobody left to watch it falls back to a fixed camera rather than a first-person view of nobody, which is the "sky in every direction" screenshot.

A timed camera is the server's own choice, and the per-tick "is this target still allowed" retarget leaves it alone. The freeze camera shows your killer, who is by definition on the other side, which is exactly the target `force_camera 1` forbids ([history](history.md#nobody-saw-who-shot-them)).

## Keyed by `String`, and `on_leave` is called after the roster drops them

The replacement target is chosen from `participants_fn`, so a game that reports the departure before removing the player picks the player who just left. Documented at the method, because it is the kind of ordering nobody guesses right twice.

## A mirror is told, records its own history, and refuses to start the chain

A client's manager is a mirror (`authoritative = false`): the server sends each view with `to_wire` and the client `apply_wire`s it and computes the camera from the players it already draws. Three rules follow, each from a game that hit the opposite:

- **The wire carries the death position** (`"d"`). The death camera is the one mode whose place is not a player the mirror is drawing; without it every client drew every death camera from the world origin. Two games carry it in their own events rather than the view's wire form (mg-smash-copter's `SPECTATE` event, mg-buses-from-hell's `adopt`) and keep their compact formats. A view from an older build with no `"d"` keeps the place the mirror had.
- **A mirror records the history when there is a delay.** With `delay_ticks > 0`, `camera_of` samples the ring and nothing else, and a mirror whose `advance` returned before recording drew every followed camera at identity the moment a server turned the delay on. The ring on a mirror is the delay's display. Its integrity is still the server's: a client sent live positions has them whatever its camera shows, so a server that means the delay withholds them from a spectator.
- **`on_death` on a mirror is refused with a `push_error`.** A mirror's `advance` runs no timers, so a chain started there is a death camera that never hands over. It is a wiring mistake, so it is the programmer's error rather than a log line. A game whose server sends no views at all (game-arena's client) runs its client manager authoritative over its own camera instead, from the kill events it already receives.

## Chase and death cameras stay out of the level

The rule above (a transform, never a camera) stays, but two modes put the camera where nobody stands: behind a target and above a body. Computed blind, the first play test (2026-10-11) had a death camera that was a frame of a teal wall. With `camera_world` set, `camera_of` pulls those two toward a pivot until they are clear of `camera_mask`, through dot-core's `DotCameraProbe`: the chase camera toward the target's eye, the death camera toward `DEATH_PIVOT_HEIGHT` (1 m) above where they fell, then re-aimed at the killer. **Unless the level is between them:** a camera clear of the wall but looking at a killer through it is still a frame of the wall, so when a ray from the camera to the killer hits `camera_mask`, the death camera stands back from the body on the side away from the killer (`DEATH_BACK_DISTANCE` 2.5 m, `DEATH_BACK_HEIGHT` 1.8 m, pulled clear the same way) and looks at the body. That is decided once per death (`_death_framing`), so a killer stepping in and out of a doorway does not cut the camera between two places. One probe per viewer, kept until `forget`, so two viewers asked for in one frame do not ease each other's cameras. The probe's easing is collision only (in quickly ahead of a wall, out slowly); it is not the smoothing ruled out below. Unset, the transform is exactly what it was, which is what a server or a 2D game wants.

## Deliberately not here

- **No camera node, no smoothing, no field-of-view.** (The probe above eases only to stay out of a wall.) A game's rig owns those, and a spectator camera that lerps is a spectator camera fighting the game's own lerp.
- **No free-camera controls.** `move_free()` takes a position and a basis; what the keys are is `DotFpsSampler`'s business, or the game's.
- **No demo recording.** dot-timer already has a replay format and a recorder; a second one here would be a second format.
- **No overview map or player list.** dot-ui, and the list comes from `targets_for()`.
- **No spectator chat channel.** dot-chat has scopes and a `membership_fn`; a "dead chat" channel is four lines there and would be a duplicate rule here.
