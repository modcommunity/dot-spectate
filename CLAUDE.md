# dot-spectate

Who is watching whom, what the server lets them watch, and where the camera is: the genre's seven observer modes, a force-camera policy, a death-cam / freeze-cam / hand-over chain, and a broadcast delay. It computes a transform and never touches a camera.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_spectate/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored). dot-team's `DotTeamSpectate` drives a `DotSpectatorManager` without naming it.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: integrity before camera, transforms not cameras, the modes and policy, the delay and its ring, the hand-over chain, `on_leave` ordering, mirrors, what is deliberately not here |
| [docs/history.md](docs/history.md) | the retarget that hid every killer, the unbounded recorder, mirrors drawing from the origin |

## Layout

| Path | What |
| --- | --- |
| `core/dot_spectator_rules.gd` | `DotSpectatorRules`: every policy (`force_camera`, `delay_ticks`, `history_ticks`, chain timings); layered `DotConfig` |
| `core/dot_spectator_view.gd` | `DotSpectatorView`: one viewer, a `Mode` and a target; its wire form carries the death position `"d"` |
| `core/dot_spectator_history.gd` | `DotSpectatorHistory`: a bounded ring of where everybody was; `sample` returns `[Transform3D, found]` |
| `runtime/dot_spectator_manager.gd` | `DotSpectatorManager`: the one node a game holds; `camera_of`, `camera_2d_of`, `on_death`, `on_leave`, `targets_for`, `move_free`, wire form |
| `dot_spectate_api.gd` | the API level (2 since `camera_world`) |
| `examples/spectate_selftest.tscn` | the suite; its "stay out of the level" section is the only one with a level |

Paths except `examples/` are in `addons/dot_spectate/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/spectate_selftest.tscn`. It prints one `push_error` on purpose (`on_death` on a mirror); any other error in its stderr is real.

## Rules that bite

- The policy and the delay are decided on the server, never by the viewing client. [design](docs/design.md#spectating-is-a-competitive-integrity-system-before-it-is-a-camera)
- Return a transform; never touch a camera node. [design](docs/design.md#it-computes-a-transform-and-never-touches-a-camera)
- Set `camera_world` (and `camera_mask` to the level's layers) on any client that draws a 3D spectator camera: chase and death cameras are then pulled out of the level by one dot-core `DotCameraProbe` per viewer. Without it a death against a wall is a frame of the wall. [design](docs/design.md#chase-and-death-cameras-stay-out-of-the-level)
- Keep the seven modes and the `force_camera` numbering; "own team" forces first person, and `_permitted_mode()` downgrades and logs rather than refuses. [design](docs/design.md#the-genres-seven-modes-and-its-numbering)
- The history ring is bounded and validated against the delay; `sample` reports not-found rather than an identity transform. [design](docs/design.md#the-delay-is-why-there-is-a-history-at-all)
- The chain always hands over, falling back to a fixed camera; the retarget sweep leaves timed cameras alone. Assert the target, not only the mode. [design](docs/design.md#the-death-cam-chain-hands-over)
- Call `on_leave` after the roster has dropped the player. [design](docs/design.md#keyed-by-string-and-on_leave-is-called-after-the-roster-drops-them)
- A mirror (`authoritative = false`) applies the wire, records its own history when there is a delay, and refuses `on_death` with a `push_error`. [design](docs/design.md#a-mirror-is-told-records-its-own-history-and-refuses-to-start-the-chain)

Deliberately not here: a camera node, smoothing (beyond the probe's collision easing), free-camera keys, demo recording, an overview map, a spectator chat channel. [design](docs/design.md#deliberately-not-here)
