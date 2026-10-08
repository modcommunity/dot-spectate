This is the **spectate** asset for TMC's **Dot** collection. It adds the part of a multiplayer game that decides who may watch whom, what they are allowed to see, and where the camera goes.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## What it does
When a player dies, or has not joined a side, they watch somebody else. This addon decides who they may watch, which camera they get, and where that camera is. It does not move a camera itself: it gives you a `Transform3D` (or a 2D position and angle) and your game puts its camera there.

Most of it is about fairness, because a spectator view is an easy way to cheat. A dead player can call out where the enemy is, and a streamer's viewers can read the map. So the server decides:

- **Who may be watched.** `force_camera` is `0` for everybody, `1` for your own team only (the default) or `2` for nobody (only the map's fixed cameras), the same numbering as the `mp_forcecamera` cvar. Own team only also forces first person, because a camera behind a teammate can see round corners they cannot.
- **How late the picture is.** `delay_ticks` makes the camera show the past, so a spectator is not watching live. A broadcast often uses ninety seconds, and a competitive server a few.

When a player dies they get a short **death cam** on where they fell, then a **freeze cam** on their killer, then first person on a teammate. If the person they are watching dies or leaves, they are moved to somebody else.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The easiest way to get this addon and the ones it needs is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap), which clones every project and links the addons into each one.

To add it to your own project by hand, copy `addons/dot_spectate/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into it and enable dot-spectate in **Project → Project Settings → Plugins**. dot-core is the only dependency.

## Using it

```gdscript
var spectate := DotSpectatorManager.new()
spectate.participants_fn = roster.keys        # () -> PackedStringArray
spectate.team_fn = match_node.team_of         # (key) -> int
spectate.alive_fn = world.is_alive            # (key) -> bool
spectate.pose_fn = world.eye_transform_of     # (key) -> Transform3D, the eyes and not the feet
spectate.setup()
add_child(spectate)

spectate.on_death("ada", where_they_fell, "bob", tick)   # starts the death cam chain
spectate.on_spawn("ada")                                 # back to playing
spectate.on_leave("ada")                                 # after the roster has dropped them

spectate.advance(tick)                                   # once a tick
camera.global_transform = spectate.camera_of(me)         # once a frame
```

A 2D game uses `camera_2d_of(me)`, which gives a position and an angle.

A spectator moves between targets with `next_target(me)` and `previous_target(me)`, and changes camera with `set_mode(me, DotSpectatorView.Mode.CHASE)`. The modes are `FIRST_PERSON`, `CHASE`, `FIXED` (the map's `fixed_cameras`), `ROAMING` (`move_free()`), and the two timed ones, `DEATH_CAM` and `FREEZE_CAM`. A mode the rules do not allow is changed to one they do.

A client builds its list of names from `targets_for(me)` and can ask `may_watch(me, them)` before offering one, so it never shows a name the server would refuse. `target_filter` adds a rule of your own, `(viewer, target) -> bool`. The server sends each viewer their view with `to_wire(key)`, and the client's manager, with `authoritative` set to false, loads it with `apply_wire()`.

Signals: `view_changed`, `retargeted` (their target went away) and `timed_out` (a death or freeze cam ended).

## Settings
The rules live in a `DotSpectatorRules` resource, set on the manager's `rules` (it makes a default one if you do not). Like every Dot config it is layered: inspector defaults, then a JSON file, then the environment, then the command line. Call `load_layered()` on it before `setup()` to apply them:

```gdscript
var rules := DotSpectatorRules.new()
rules.load_layered("user://spectate.json")
spectate.rules = rules
```

```bash
DOT_SPECTATE_FORCE_CAMERA=0 godot --headless -- --spectate-delay-ticks=640
```

| Setting | Default | What it does |
| --- | --- | --- |
| `force_camera` | 1 | Who may be watched: 0 everybody, 1 own team (and first person only), 2 nobody |
| `allow_while_dead` | true | A dead player may spectate before the round ends |
| `allow_unassigned` | true | A player on no team may spectate |
| `allow_while_alive` | false | A living player may spectate (for replay viewers) |
| `allow_roaming` | false | Offer a free camera. Only works with `force_camera` 0 |
| `death_cam_ticks` | 128 | How long the death cam holds (2 seconds at 64 ticks) |
| `freeze_cam_ticks` | 192 | How long the freeze cam holds on the killer (3 seconds). 0 skips it |
| `chase_distance` | 3.5 | How far behind the target the chase camera sits |
| `chase_height` | 0.8 | How far above them |
| `auto_retarget` | true | Move a spectator on when their target dies or leaves |
| `cycle_includes_dead` | false | Dead players are in the cycle |
| `delay_ticks` | 0 | How far behind live the camera is. 0 is live |
| `history_ticks` | 128 | How much pose history to keep. Raised to `delay_ticks + 1` if lower |

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/spectate_selftest.tscn
```

## License
MIT. See [LICENSE](LICENSE).
